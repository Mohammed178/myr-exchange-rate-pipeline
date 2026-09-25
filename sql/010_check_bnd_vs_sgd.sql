-- 010_check_bnd_vs_sgd.sql
-- BND is pegged 1:1 to SGD, so middle rates should match.
-- Result: BND deviates by -0.4% to +1.4% in Apr-May 2018, so BNM's BND quote is treated as indicative.
select b.date,
       b.rate as bnd_middle,
       s.rate as sgd_middle,
       round(100 * (b.rate - s.rate) / s.rate, 3) as diff_pct
from public.exchange_rates b
join public.exchange_rates s
  on s.date = b.date and s.currency = 'SGD' and s.rate_type = 'middle'
where b.currency = 'BND'
  and b.rate_type = 'middle'
  and b.date between '2018-04-20' and '2018-05-10'
order by b.date;
