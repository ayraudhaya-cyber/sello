-- =============================================================================
-- 043 — First-time Owner workspace setup
--
-- Company-level flag so a newly provisioned Owner is guided through a short
-- setup flow. Existing tenants are marked complete and are not forced through.
-- New company_settings rows default to incomplete (false).
-- =============================================================================

alter table public.company_settings
  add column if not exists owner_setup_completed boolean not null default false;

comment on column public.company_settings.owner_setup_completed is
  'When true, the company Owner has finished first-time workspace setup.';

-- Existing tenants already using Sello must not see the new setup flow.
update public.company_settings
set owner_setup_completed = true
where owner_setup_completed is distinct from true;

-- Owners can update their company name / legal name during setup (and later).
drop policy if exists "companies_update_own" on public.companies;
create policy "companies_update_own"
  on public.companies
  for update
  to authenticated
  using (
    id = public.current_company_id()
    and public.current_role_code() = 'owner'
  )
  with check (
    id = public.current_company_id()
    and public.current_role_code() = 'owner'
  );

-- Owners (and managers) can update Head Office phone / address.
drop policy if exists "branches_update_own_company" on public.branches;
create policy "branches_update_own_company"
  on public.branches
  for update
  to authenticated
  using (
    company_id = public.current_company_id()
    and public.current_role_code() in ('owner', 'manager')
    and deleted_at is null
  )
  with check (
    company_id = public.current_company_id()
    and public.current_role_code() in ('owner', 'manager')
  );
