-- 007_check_unit_changes.sql
-- Day-over-day moves too large to be ordinary market moves.
-- Each hit must be checked against real-world events before deciding it is an error.
-- Findings: CNY 2005-05-05 (source error, see 008) and MMK 2012-04-03 (real devaluation, kept).
select date, currency, prev_rate, rate, pct_change
from public.v_daily_change
where abs(pct_change) > 50
order by date;
