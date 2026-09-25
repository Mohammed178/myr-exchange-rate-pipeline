-- 009_largest_spreads.sql
-- The widest buy/sell spreads in the history, used to investigate spikes on the spread chart.
-- Findings: EGP November 2016 (Egypt floated the pound on 3 Nov 2016, real event)
-- and BND April-May 2018 (loosely maintained quote, see 010).
select date, currency, buying, selling, spread_pct
from public.v_spread
order by spread_pct desc
limit 10;
