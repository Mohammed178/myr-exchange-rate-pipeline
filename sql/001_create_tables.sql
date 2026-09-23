-- 001_create_tables.sql
-- Core tables for the BNM exchange rate pipeline (data.gov.my: exchangerates_daily_0900)

-- Rates in LONG format: one row per (date, rate_type, currency).
-- The API returns 27 currency columns; the Python step reshapes them into rows,
-- and drops null rates before loading.
create table if not exists public.exchange_rates (
    date        date          not null,
    rate_type   text          not null check (rate_type in ('buying', 'selling', 'middle')),
    currency    char(3)       not null check (currency ~ '^[A-Z]{3}$'),
    rate        numeric(18,8) not null check (rate > 0),
    loaded_at   timestamptz   not null default now(),
    -- The primary key makes the load idempotent: re-running a day upserts instead of duplicating
    primary key (date, rate_type, currency)
);

comment on table public.exchange_rates is
  'BNM daily 0900 MYR exchange rates. Ringgit is the numerator: higher rate = weaker MYR.';

-- One row per pipeline run, written by the Python script (start -> success/failed).
create table if not exists public.pipeline_runs (
    id             bigint generated always as identity primary key,
    started_at     timestamptz not null default now(),
    finished_at    timestamptz,
    status         text        not null default 'running'
                               check (status in ('running', 'success', 'failed')),
    rows_fetched   integer,
    rows_upserted  integer,
    latest_date    date,        -- newest date present in the API response
    error_message  text
);
