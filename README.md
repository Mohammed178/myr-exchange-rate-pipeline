# MYR Exchange Rate Pipeline

A scheduled, validated data pipeline that loads Bank Negara Malaysia's daily exchange rates into Postgres every weekday.

**Source:** [data.gov.my](https://data.gov.my) Open API, dataset `exchangerates_daily_0900` (BNM rates at 09:00, 2003 to present, 27 currencies, buying / middle / selling).

## How it works

```
data.gov.my API ──> fetch.py ──> load.py ──> Supabase Postgres ──> SQL views ──> dashboard
                    (fetch,       (correct,     (exchange_rates,
                     reshape)      validate,     pipeline_runs)
                                   upsert, log)
        ▲
GitHub Actions cron, 18:00 MYT, Mon to Fri
```

- **Fetch** calls the API with retries on rate limits and server errors, then reshapes the wide response (one column per currency) into long format: `(date, rate_type, currency, rate)`.
- **Validate** stops the run on structural problems (bad rate types, malformed currency codes, duplicate keys) and warns on source-data anomalies.
- **Load** upserts on the primary key `(date, rate_type, currency)`, so re-running any day is safe. Each daily run re-fetches the last 7 days, so a missed or failed run heals itself on the next one.
- **Log** writes every run to `pipeline_runs` with its status, row counts and any error. A failed run exits non-zero, so it shows as failed in GitHub Actions.

## Data quality findings

About 383,000 rows loaded (2003 to present). Issues found in the source data, and how each is handled:

| Finding | Rows | Handling |
|---|---|---|
| XDR (IMF Special Drawing Rights) is published with a middle rate only | every day | Expected; excluded from spread and completeness checks |
| Buying and selling labels swapped at source (2004-04-16, 2004-12-07, 2005-01-10) | 10 | Corrected: the middle rate sits exactly between the pair, confirming a swap |
| 2005-01-10 HKD / JPY / SGD spreads around 0.01%, against a normal ~2% | 3 | Kept; likely a different pricing basis that day |
| SAR selling rate on 2020-11-06 below both buying and middle | 1 | Kept and flagged; true value unknown (SAR is pegged to USD, so ~1.10 expected) |

## Repository layout

```
pipeline/
  fetch.py            API client and wide-to-long reshape
  load.py             entry point: correct, validate, upsert, log
  requirements.txt
  .env.example
sql/
  001_create_tables.sql
  002_indexes.sql
  003_rls_policies.sql
  004_views.sql       latest rates, daily change, monthly summary, 30-day MA, spread, pipeline health
  005_validation_checks.sql
.github/workflows/
  daily-load.yml      scheduled run
```

## Running it

1. Run the SQL files in `sql/` in order in the Supabase SQL Editor (skip `005`, which holds manual checks).
2. `cd pipeline`, `pip install -r requirements.txt`, then copy `.env.example` to `.env` and fill it in.
3. `python load.py --backfill` loads the full history once; `python load.py` loads the last 7 days.
4. For scheduling, add `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` as GitHub Actions repository secrets.

## Note on direction

The ringgit is the numerator: a **higher** rate means a **weaker** ringgit.
