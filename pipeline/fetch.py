"""
fetch.py — pull BNM daily exchange rates from data.gov.my and reshape them for Supabase.

Source : https://api.data.gov.my/data-catalogue?id=exchangerates_daily_0900
Shape  : the API returns WIDE rows (date, rate_type, USD, SGD, EUR, ...).
         This module returns a LONG DataFrame (date, rate_type, currency, rate),
         which is what the exchange_rates table expects.

Note   : the ringgit is the numerator, so a HIGHER rate means a WEAKER ringgit.
"""

import time
from datetime import date, timedelta

import pandas as pd
import requests

BASE_URL = "https://api.data.gov.my/data-catalogue"
DATASET_ID = "exchangerates_daily_0900"

# Non-currency columns in the API response; everything else is a currency code.
META_COLUMNS = {"date", "rate_type"}

TIMEOUT = 30          # seconds to wait for a response before giving up
MAX_RETRIES = 3       # retries for rate limits (429) and server errors (5xx)
BACKOFF_SECONDS = 5   # wait between retries, multiplied by the attempt number


def fetch_raw(date_start=None, date_end=None, limit=None):
    """Call the API once and return the parsed JSON records (wide format).

    date_start / date_end: datetime.date or 'YYYY-MM-DD' string, both inclusive.
    limit: maximum rows to return; leave as None to let the API decide.
    """
    params = {"id": DATASET_ID, "sort": "date"}

    # The API expects the date filters in the form '<YYYY-MM-DD>@<column>'.
    if date_start:
        params["date_start"] = f"{date_start}@date"
    if date_end:
        params["date_end"] = f"{date_end}@date"
    if limit:
        params["limit"] = limit

    for attempt in range(1, MAX_RETRIES + 1):
        response = requests.get(BASE_URL, params=params, timeout=TIMEOUT)

        # 429 = rate limited, 5xx = their side broke. Both are worth retrying.
        if response.status_code == 429 or response.status_code >= 500:
            if attempt == MAX_RETRIES:
                response.raise_for_status()
            time.sleep(BACKOFF_SECONDS * attempt)
            continue

        # Anything else that is not a success should fail loudly, right here.
        response.raise_for_status()
        return response.json()

    return []


def reshape_to_long(records):
    """Turn wide API records into (date, rate_type, currency, rate) rows."""
    if not records:
        return pd.DataFrame(columns=["date", "rate_type", "currency", "rate"])

    wide = pd.DataFrame(records)

    currency_columns = [c for c in wide.columns if c not in META_COLUMNS]

    long = wide.melt(
        id_vars=["date", "rate_type"],
        value_vars=currency_columns,
        var_name="currency",
        value_name="rate",
    )

    long["date"] = pd.to_datetime(long["date"]).dt.date
    long["currency"] = long["currency"].str.upper()
    long["rate"] = pd.to_numeric(long["rate"], errors="coerce")

    # The table rejects nulls and non-positive rates, so drop them before loading.
    long = long.dropna(subset=["rate"])
    long = long[long["rate"] > 0]

    return long.reset_index(drop=True)


def fetch_rates(date_start=None, date_end=None):
    """Fetch a date range and return it as a long DataFrame. This is the entry point."""
    records = fetch_raw(date_start=date_start, date_end=date_end)
    return reshape_to_long(records)


def fetch_recent(days=7):
    """Fetch the last N days. Used by the scheduled daily run, with overlap
    so a missed run is backfilled automatically on the next one."""
    end = date.today()
    start = end - timedelta(days=days)
    return fetch_rates(date_start=start, date_end=end)


def fetch_backfill(start_year=2003, chunk_years=1):
    """Fetch the full history in chunks, to stay well under the rate limit."""
    frames = []
    year = start_year
    current_year = date.today().year

    while year <= current_year:
        chunk_end_year = min(year + chunk_years - 1, current_year)
        print(f"Fetching {year}-01-01 to {chunk_end_year}-12-31 ...")

        frame = fetch_rates(
            date_start=f"{year}-01-01",
            date_end=f"{chunk_end_year}-12-31",
        )
        print(f"  {len(frame):,} rows")
        frames.append(frame)

        year = chunk_end_year + 1
        time.sleep(1)  # be polite to a free public API

    if not frames:
        return pd.DataFrame(columns=["date", "rate_type", "currency", "rate"])

    return pd.concat(frames, ignore_index=True)


if __name__ == "__main__":
    # Smoke test: run `python fetch.py` and inspect what comes back.
    df = fetch_recent(days=7)

    print(df.head())
    print(f"\nrows: {len(df):,}")
    print(f"dates: {df['date'].min()} to {df['date'].max()}")
    print(f"currencies: {df['currency'].nunique()}")
    print(f"rate types: {sorted(df['rate_type'].unique())}")
