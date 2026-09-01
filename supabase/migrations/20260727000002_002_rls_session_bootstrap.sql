-- =============================================================================
-- Migration 002 — Enable RLS on employees (session bootstrap)
--
-- Without SELECT policies, authenticated queries return zero rows even when
-- the data exists. This migration enables RLS and adds the minimum policy
-- needed for AppSession creation: an employee can read their own row (matched
-- by auth.uid() = user_id) with related company, branch, and role via FK joins.
-- =============================================================================

-- Enable RLS on the tables the employee lookup touches.
alter table public.employees enable row level security;
alter table public.companies enable row level security;
alter table public.branches enable row level security;
alter table public.roles enable row level security;
alter table public.company_settings enable row level security;

-- employees: a user can read their own employee row.
create policy "employees_select_own"
  on public.employees
  for select
  to authenticated
  using (user_id = auth.uid());

-- companies: an employee can read their own company.
create policy "companies_select_own"
  on public.companies
  for select
  to authenticated
  using (
    id in (
      select company_id from public.employees
      where user_id = auth.uid()
        and deleted_at is null
    )
  );

-- branches: an employee can read branches in their company.
create policy "branches_select_own_company"
  on public.branches
  for select
  to authenticated
  using (
    company_id in (
      select company_id from public.employees
      where user_id = auth.uid()
        and deleted_at is null
    )
  );

-- roles: all authenticated users can read roles (global catalog).
create policy "roles_select_all"
  on public.roles
  for select
  to authenticated
  using (true);

-- company_settings: an employee can read their company settings.
create policy "company_settings_select_own"
  on public.company_settings
  for select
  to authenticated
  using (
    company_id in (
      select company_id from public.employees
      where user_id = auth.uid()
        and deleted_at is null
    )
  );
