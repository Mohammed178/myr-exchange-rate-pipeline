-- 005_validation_checks.sql
-- Data-quality checks. Run manually in the SQL editor; each should return 0 rows
-- (or only explainable rows). Good material for the project README.

-- 1. Selling rate below buying rate (should never happen; would imply arbitrage)
select b.date, b.currency, b.rate as buying, s.rate as selling
from public.exchange_rates b
join public.exchange_rates s
  on s.date = b.date and s.currency = b.currency and s.rate_type = 'selling'
where b.rate_type = 'buying'
  and s.rate < b.rate;

-- 2. Middle rate outside the buying/selling range
select m.date, m.currency, m.rate as middle, b.rate as buying, s.rate as selling
from public.exchange_rates m
join public.exchange_rates b on b.date = m.date and b.currency = m.currency and b.rate_type = 'buying'
join public.exchange_rates s on s.date = m.date and s.currency = m.currency and s.rate_type = 'selling'
where m.rate_type = 'middle'
  and m.rate not between b.rate and s.rate;

-- 3. Suspicious jumps: more than 5% move in one trading day (review, don't auto-delete)
select date, currency, prev_rate, rate, pct_change
from public.v_daily_change
where abs(pct_change) > 5
order by abs(pct_change) desc;

-- 4. Missing weekdays (expect Malaysian public holidays here, not bugs)
select d::date as missing_date
from generate_series(
        (select min(date) from public.exchange_rates),
        (select max(date) from public.exchange_rates),
        interval '1 day'
     ) d
where extract(dow from d) not in (0, 6)
  and not exists (select 1 from public.exchange_rates e where e.date = d::date)
order by missing_date desc;

-- 5. Days with an incomplete set of rate types for a currency
--    (XDR is excluded: it is the IMF's SDR and BNM publishes a middle rate only)
select date, currency, count(*) as rate_types
from public.exchange_rates
where currency <> 'XDR'
group by date, currency
having count(*) <> 3
order by date desc;

-- 6. Row counts per year (spot gaps in the historical backfill)
select extract(year from date)::int as year, count(*) as rows, count(distinct date) as days
from public.exchange_rates
group by 1
order by 1;
