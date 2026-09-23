-- 003_rls_policies.sql
-- Public read-only access for the dashboard.
-- Writes come ONLY from the pipeline using the service_role key (bypasses RLS).
-- Keep the service_role key in GitHub Actions secrets; never ship it to a frontend.

alter table public.exchange_rates enable row level security;
alter table public.pipeline_runs  enable row level security;

drop policy if exists "Public read exchange_rates" on public.exchange_rates;
create policy "Public read exchange_rates"
    on public.exchange_rates for select
    to anon, authenticated
    using (true);

drop policy if exists "Public read pipeline_runs" on public.pipeline_runs;
create policy "Public read pipeline_runs"
    on public.pipeline_runs for select
    to anon, authenticated
    using (true);
-- No insert/update/delete policies = those actions are blocked for anon/authenticated.
