-- 008_remove_bad_cny_2005.sql
-- CNY rates before 2005-05-05 were published as the product of the two USD pegs
-- (3.80 x 8.2765 = 31.45) instead of the cross rate (3.80 / 8.2765 = 0.4591).
-- load.py also drops these rows (drop_known_bad_rows) so future backfills stay clean.
delete from public.exchange_rates
where currency = 'CNY'
  and date < '2005-05-05';
