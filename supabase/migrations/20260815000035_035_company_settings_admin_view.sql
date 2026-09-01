-- =============================================================================
-- 035 — Admin view: company_settings with company identity
--
-- Postgres cannot join companies.name into the company_settings base table
-- without duplicating tenant data. This read-only view is for the Supabase
-- Table Editor / SQL Editor so operators can see company_code and name
-- without matching UUIDs across tables.
-- =============================================================================

create or replace view public.company_settings_admin
with (security_invoker = true) as
select
  c.company_code,
  c.name as company_name,
  c.legal_name,
  cs.*
from public.company_settings cs
join public.companies c on c.id = cs.company_id;

comment on view public.company_settings_admin is
  'Read-only join of company_settings with companies identity columns for dashboard / SQL identification. Not used by the app.';

grant select on public.company_settings_admin to authenticated;
