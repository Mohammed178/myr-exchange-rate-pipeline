"""
load.py — run the pipeline: fetch -> validate -> upsert into Supabase -> log the run.

Usage:
    python load.py              # daily run: last 7 days (overlap self-heals missed runs)
    python load.py --backfill   # one-off: full history since 2003

Needs two environment variables (a local .env file, or GitHub Actions secrets):
    SUPABASE_URL
    SUPABASE_SERVICE_ROLE_KEY   # service role bypasses RLS; never commit or expose it
"""

import argparse
import os
import sys
from datetime import date, datetime, timezone

from dotenv import load_dotenv
from supabase import create_client

from fetch import fetch_backfill, fetch_recent

RATES_TABLE = "exchange_rates"
RUNS_TABLE = "pipeline_runs"
BATCH_SIZE = 1000                     # rows per upsert request
VALID_RATE_TYPES = {"buying", "middle", "selling"}
MIDDLE_ONLY = {"XDR"}                 # IMF SDR: BNM publishes a middle rate only
CNY_FIRST_GOOD_DATE = date(2005, 5, 5)  # earlier CNY rates are wrong at source


def get_client():
    load_dotenv()  # reads .env locally; does nothing in GitHub Actions
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(url, key)


# ---------- run logging ----------

def start_run(client):
    """Insert a 'running' row and return its id."""
    result = client.table(RUNS_TABLE).insert({"status": "running"}).execute()
    return result.data[0]["id"]


def finish_run(client, run_id, status, **fields):
    """Close the run row with its outcome."""
    payload = {
        "status": status,
        "finished_at": datetime.now(timezone.utc).isoformat(),
        **fields,
    }
    client.table(RUNS_TABLE).update(payload).eq("id", run_id).execute()


# ---------- corrections ----------

def drop_known_bad_rows(df):
    """Drop rows the source is known to have published wrongly.
    CNY before 2005-05-05 is 3.80 x 8.2765 (the two USD pegs multiplied)
    instead of the cross rate 3.80 / 8.2765. See sql/008_remove_bad_cny_2005.sql."""
    bad = (df["currency"] == "CNY") & (df["date"] < CNY_FIRST_GOOD_DATE)
    if bad.any():
        print(f"Dropped {bad.sum()} known-bad CNY rows before {CNY_FIRST_GOOD_DATE}")
    return df[~bad]


def fix_swapped_spreads(df):
    """Some historical days have buying/selling labels swapped at source.
    Where buying > selling and the middle rate sits between them, swap them back."""
    wide = df.pivot_table(index=["date", "currency"], columns="rate_type", values="rate")
    swapped = wide[
        (wide["buying"] > wide["selling"])
        & (wide["middle"] <= wide["buying"])
        & (wide["middle"] >= wide["selling"])
    ].index
    if len(swapped) == 0:
        return df
    df = df.copy()
    in_swapped = df.set_index(["date", "currency"]).index.isin(swapped)
    df.loc[in_swapped, "rate_type"] = df.loc[in_swapped, "rate_type"].replace(
        {"buying": "selling", "selling": "buying"}
    )
    print(f"Corrected {len(swapped)} swapped buying/selling pairs")
    return df


# ---------- validation ----------

def validate(df):
    """Fail before loading if the data is structurally wrong.
    The database constraints are the last line of defence; this is the first."""
    problems = []

    bad_types = set(df["rate_type"]) - VALID_RATE_TYPES
    if bad_types:
        problems.append(f"unexpected rate_type values: {bad_types}")

    bad_codes = df.loc[~df["currency"].str.fullmatch(r"[A-Z]{3}"), "currency"].unique()
    if len(bad_codes):
        problems.append(f"malformed currency codes: {list(bad_codes)}")

    dupes = df.duplicated(subset=["date", "rate_type", "currency"]).sum()
    if dupes:
        problems.append(f"{dupes} duplicate (date, rate_type, currency) rows")

    # Spread sanity: buying <= middle <= selling (XDR has no buying/selling)
    pivot = (
        df[~df["currency"].isin(MIDDLE_ONLY)]
        .pivot_table(index=["date", "currency"], columns="rate_type", values="rate")
        .dropna()
    )
    if not pivot.empty:
        broken = pivot[(pivot["buying"] > pivot["middle"]) | (pivot["middle"] > pivot["selling"])]
        if len(broken):
            # Source-data anomaly, not a code bug: warn and load as-is.
            # SQL checks 1 and 2 in 005_validation_checks.sql keep surfacing these.
            print(f"WARNING: {len(broken)} rows where buying <= middle <= selling fails:")
            print(broken.to_string())

    if problems:
        raise ValueError("Validation failed: " + "; ".join(problems))


# ---------- loading ----------

def to_records(df):
    """Convert the DataFrame into JSON-safe dicts for the Supabase client."""
    return [
        {
            "date": row.date.isoformat(),
            "rate_type": row.rate_type,
            "currency": row.currency,
            "rate": float(row.rate),
        }
        for row in df.itertuples(index=False)
    ]


def upsert_rates(client, df):
    """Upsert in batches. The primary key makes re-loading the same day harmless."""
    records = to_records(df)
    for i in range(0, len(records), BATCH_SIZE):
        batch = records[i : i + BATCH_SIZE]
        client.table(RATES_TABLE).upsert(
            batch, on_conflict="date,rate_type,currency"
        ).execute()
        print(f"  upserted {i + len(batch):,} / {len(records):,}")
    return len(records)


# ---------- entry point ----------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backfill", action="store_true", help="load full history since 2003")
    args = parser.parse_args()

    client = get_client()
    run_id = start_run(client)

    try:
        df = fetch_backfill() if args.backfill else fetch_recent(days=7)
        print(f"Fetched {len(df):,} rows")

        # An empty result is a failure: even over a long holiday, 7 days has data.
        if df.empty:
            raise ValueError("API returned no rows")

        df = drop_known_bad_rows(df)
        df = fix_swapped_spreads(df)
        validate(df)
        upserted = upsert_rates(client, df)

        finish_run(
            client,
            run_id,
            "success",
            rows_fetched=len(df),
            rows_upserted=upserted,
            latest_date=df["date"].max().isoformat(),
        )
        print(f"Done: {upserted:,} rows, latest date {df['date'].max()}")

    except Exception as exc:
        finish_run(client, run_id, "failed", error_message=str(exc)[:1000])
        print(f"FAILED: {exc}", file=sys.stderr)
        sys.exit(1)  # non-zero exit makes the GitHub Actions run show as failed


if __name__ == "__main__":
    main()
