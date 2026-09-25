-- 011_data_quality_log.sql
-- A documented log of every data-quality finding: what it was, the evidence, and what was done.
-- Lives in the database so the Power BI data-quality page and the README share one source.

create table if not exists public.data_quality_log (
    id             int  generated always as identity primary key,
    finding        text not null,
    currency       text not null,
    period         text not null,
    rows_affected  int,
    category       text not null check (category in ('Source error', 'Real event', 'Source limitation', 'By design')),
    action         text not null check (action in ('Corrected', 'Removed', 'Flagged', 'Kept', 'Excluded from checks')),
    evidence       text not null
);

insert into public.data_quality_log (finding, currency, period, rows_affected, category, action, evidence) values
('Buying and selling labels swapped', 'CHF, EUR, GBP, HKD, JPY, SGD', '2004-04-16 to 2005-01-10', 10,
 'Source error', 'Corrected',
 'Middle rate sits exactly between the swapped pair: EUR 2004-04-16, (4.5413 + 4.4843) / 2 = 4.5128 vs published 4.5126'),

('Unusually narrow spreads (about 0.01%)', 'HKD, JPY, SGD', '2005-01-10', 3,
 'Source limitation', 'Kept',
 'Spreads around 0.01% against a normal ~2%; likely a different pricing basis that day'),

('CNY published as the product of the two USD pegs', 'CNY', 'Before 2005-05-05', null,
 'Source error', 'Removed',
 'Published 31.4465 = 3.80 x 8.2765; correct cross rate is 3.80 / 8.2765 = 0.4591, the value from 5 May 2005'),

('Selling rate below both buying and middle', 'SAR', '2020-11-06', 1,
 'Source error', 'Flagged',
 'Middle is not the midpoint of buying and selling; SAR is pegged to USD, implying about 1.10, not 1.0846'),

('99% one-day drop in rate', 'MMK', '2012-04-03', null,
 'Real event', 'Kept',
 'Myanmar moved from a fixed ~6.4 to a managed float ~818 kyat per USD in April 2012; rates match both regimes'),

('Spreads up to 6.9% for several weeks', 'EGP', 'November 2016', null,
 'Real event', 'Kept',
 'Egypt floated the pound on 3 November 2016; spreads widen from the first trading days after the float'),

('Pegged rate drifting from its anchor', 'BND', 'April to May 2018', null,
 'Source limitation', 'Kept',
 'BND is pegged 1:1 to SGD but deviates by -0.4% to +1.4% with a spread up to 3.7%; treat as indicative'),

('Middle rate only, no buying or selling', 'XDR', 'All dates', null,
 'By design', 'Excluded from checks',
 'XDR is the IMF''s Special Drawing Right, a reserve asset with no retail market');

-- Read access: public (dashboard) and the Power BI login
alter table public.data_quality_log enable row level security;

drop policy if exists "Public read data_quality_log" on public.data_quality_log;
create policy "Public read data_quality_log"
    on public.data_quality_log for select
    to anon, authenticated
    using (true);

drop policy if exists "Power BI read data_quality_log" on public.data_quality_log;
create policy "Power BI read data_quality_log"
    on public.data_quality_log for select
    to powerbi_reader
    using (true);

grant select on public.data_quality_log to powerbi_reader;
