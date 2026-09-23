-- 004_views.sql
-- Analytical views for the dashboard. security_invoker makes views respect RLS.

-- Latest middle rate per currency
create or replace view public.v_latest_rates with (security_invoker = on) as
select distinct on (currency)
    currency,
    date,
    rate
from public.exchange_rates
where rate_type = 'middle'
order by currency, date desc;

-- Day-over-day change (previous TRADING day, so weekends/holidays are skipped naturally)
create or replace view public.v_daily_change with (security_invoker = on) as
select
    date,
    currency,
    rate,
    lag(rate) over w as prev_rate,
    round(100.0 * (rate - lag(rate) over w) / nullif(lag(rate) over w, 0), 4) as pct_change
from public.exchange_rates
where rate_type = 'middle'
window w as (partition by currency order by date);

-- Monthly summary per currency
create or replace view public.v_monthly_summary with (security_invoker = on) as
select
    date_trunc('month', date)::date as month,
    currency,
    round(avg(rate), 6) as avg_rate,
    min(rate)           as min_rate,
    max(rate)           as max_rate,
    count(*)            as trading_days
from public.exchange_rates
where rate_type = 'middle'
group by 1, 2;

-- 30-trading-day moving average (smooths noise for trend charts)
create or replace view public.v_moving_avg_30d with (security_invoker = on) as
select
    date,
    currency,
    rate,
    round(avg(rate) over (
        partition by currency order by date
        rows between 29 preceding and current row
    ), 6) as ma_30d
from public.exchange_rates
where rate_type = 'middle';

-- Buying/selling spread (a wide spread can signal market stress)
create or replace view public.v_spread with (security_invoker = on) as
select
    b.date,
    b.currency,
    b.rate as buying,
    s.rate as selling,
    s.rate - b.rate as spread,
    round(100.0 * (s.rate - b.rate) / nullif(b.rate, 0), 4) as spread_pct
from public.exchange_rates b
join public.exchange_rates s
  on s.date = b.date and s.currency = b.currency and s.rate_type = 'selling'
where b.rate_type = 'buying';

-- Pipeline health: is the data fresh, and did the last run succeed?
create or replace view public.v_pipeline_health with (security_invoker = on) as
select
    (select max(date) from public.exchange_rates)                  as latest_data_date,
    current_date - (select max(date) from public.exchange_rates)   as days_since_latest,
    r.started_at  as last_run_at,
    r.status      as last_run_status,
    r.rows_upserted,
    r.error_message
from (
    select * from public.pipeline_runs order by started_at desc limit 1
) r;
