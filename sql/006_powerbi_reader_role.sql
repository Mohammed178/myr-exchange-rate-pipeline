-- 006_powerbi_reader_role.sql
-- Read-only login for Power BI. Replace CHANGE_ME before running; never commit the real password.
-- Connect through the Supabase Session pooler (port 5432) as powerbi_reader.<project-ref>.

create role powerbi_reader with login password 'CHANGE_ME';

grant usage on schema public to powerbi_reader;
grant select on
    public.exchange_rates, public.pipeline_runs,
    public.v_latest_rates, public.v_daily_change, public.v_monthly_summary,
    public.v_moving_avg_30d, public.v_spread, public.v_pipeline_health
to powerbi_reader;

-- RLS is enabled, so the role also needs read policies (the views use security_invoker)
create policy "Power BI read exchange_rates" on public.exchange_rates
    for select to powerbi_reader using (true);
create policy "Power BI read pipeline_runs" on public.pipeline_runs
    for select to powerbi_reader using (true);
