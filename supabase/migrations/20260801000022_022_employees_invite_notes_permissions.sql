-- =============================================================================
-- 022 — Employees invite / notes / role module foundation
--
-- Extends people domain without changing Hub V1 UX ownership.
-- Notes prepare profile docs later; role_module_access prepares custom ACL.
-- =============================================================================

alter table public.employees
  add column if not exists notes text;

alter table public.employees
  drop constraint if exists employees_notes_not_blank;

alter table public.employees
  add constraint employees_notes_not_blank
    check (notes is null or length(trim(notes)) > 0);

comment on column public.employees.notes is
  'Free-form HR notes. Documents / attachments come later.';

-- Future custom / per-company module grants (V1 still uses RolePermissionProfile).
create table if not exists public.role_module_access (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies (id) on delete cascade,
  role_id uuid not null references public.roles (id) on delete cascade,
  module_key text not null,
  can_view boolean not null default true,
  can_manage boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint role_module_access_module_key_not_blank
    check (length(trim(module_key)) > 0)
);

-- Global defaults (company_id null) + optional per-tenant overrides.
create unique index if not exists role_module_access_global_role_module_key
  on public.role_module_access (role_id, module_key)
  where company_id is null;

create unique index if not exists role_module_access_company_role_module_key
  on public.role_module_access (company_id, role_id, module_key)
  where company_id is not null;

drop trigger if exists trg_role_module_access_set_updated_at
  on public.role_module_access;
create trigger trg_role_module_access_set_updated_at
before update on public.role_module_access
for each row execute function public.set_updated_at();

comment on table public.role_module_access is
  'Future ACL overrides. App V1 still derives access from RolePermissionProfile.';

alter table public.role_module_access enable row level security;

drop policy if exists "role_module_access_select"
  on public.role_module_access;
create policy "role_module_access_select"
  on public.role_module_access
  for select
  to authenticated
  using (
    company_id is null
    or company_id = public.current_company_id()
  );

-- Invite audit trail (auth user creation stays client-assisted for now).
create table if not exists public.employee_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  email text not null,
  invited_by uuid references public.employees (id) on delete set null,
  status text not null default 'sent',
  auth_user_id uuid,
  sent_at timestamptz not null default timezone('utc', now()),
  accepted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),

  constraint employee_invites_email_not_blank
    check (length(trim(email)) > 0),
  constraint employee_invites_status_allowed
    check (status in ('sent', 'accepted', 'revoked', 'failed'))
);

create index if not exists employee_invites_employee_idx
  on public.employee_invites (employee_id, sent_at desc);

create index if not exists employee_invites_company_idx
  on public.employee_invites (company_id, sent_at desc);

comment on table public.employee_invites is
  'Audit of login invites. Password setup uses Auth recovery email.';

alter table public.employee_invites enable row level security;

drop policy if exists "employee_invites_select_own_company"
  on public.employee_invites;
create policy "employee_invites_select_own_company"
  on public.employee_invites
  for select
  to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "employee_invites_write_own_company"
  on public.employee_invites;
create policy "employee_invites_write_own_company"
  on public.employee_invites
  for all
  to authenticated
  using (company_id = public.current_company_id())
  with check (company_id = public.current_company_id());
