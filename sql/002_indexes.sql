-- 002_indexes.sql
-- The primary key already indexes (date, rate_type, currency).
-- Dashboards mostly ask "one currency over time", so index that path too.
create index if not exists idx_exchange_rates_currency_date
    on public.exchange_rates (currency, rate_type, date desc);

create index if not exists idx_pipeline_runs_started_at
    on public.pipeline_runs (started_at desc);
