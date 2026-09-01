-- =============================================================================
-- Migration 014 — Employees domain foundation
--
-- Profile fields, employment status, company-scoped RLS, activity + assignment
-- stubs, future role seeds, and employee-avatars storage.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.employees
  add column if not exists employee_code text;

alter table public.employees
  add column if not exists nic text;

alter table public.employees
  add column if not exists address text;

alter table public.employees
  add column if not exists emergency_contact_name text;

alter table public.employees
  add column if not exists emergency_contact_phone text;

alter table public.employees
  add column if not exists department text;

alter table public.employees
  add column if not exists joined_at date;

alter table public.employees
  add column if not exists employment_status text not null default 'active';

alter table public.employees
  add column if not exists last_active_at timestamptz;

-- Future-ready placeholders (unused in Phase 1)
alter table public.employees
  add column if not exists sales_territory text;

alter table public.employees
  add column if not exists device_registration_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'employees_employment_status_allowed'
  ) then
    alter table public.employees
      add constraint employees_employment_status_allowed
        check (
          employment_status in ('active', 'inactive', 'suspended', 'archived')
        );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'employees_employee_code_not_blank'
  ) then
    alter table public.employees
      add constraint employees_employee_code_not_blank
        check (employee_code is null or length(trim(employee_code)) > 0);
  end if;
end $$;

create unique index if not exists employees_company_code_active_key
  on public.employees (company_id, employee_code)
  where employee_code is not null and deleted_at is null;

create index if not exists employees_company_status_idx
  on public.employees (company_id, employment_status)
  where deleted_at is null;

create index if not exists employees_company_role_idx
  on public.employees (company_id, role_id)
  where deleted_at is null;

-- Keep is_active in sync with employment_status for session bootstrap.
create or replace function public.sync_employee_is_active()
returns trigger
language plpgsql
as $$
begin
  new.is_active := (new.employment_status = 'active');
  return new;
end;
$$;

drop trigger if exists trg_employees_sync_is_active on public.employees;
create trigger trg_employees_sync_is_active
before insert or update of employment_status
on public.employees
for each row execute function public.sync_employee_is_active();

update public.employees
set employment_status = case when is_active then 'active' else 'inactive' end
where employment_status is null
   or employment_status not in ('active', 'inactive', 'suspended', 'archived');

comment on column public.employees.employment_status is
  'active | inactive | suspended | archived — archived staff remain for history.';
comment on column public.employees.employee_code is
  'Human-readable employee ID within the company.';
comment on column public.employees.sales_territory is
  'Reserved for future territory assignment.';
comment on column public.employees.device_registration_id is
  'Reserved for device registration / field apps.';

-- ---------------------------------------------------------------------------
-- Future role seeds (catalog only)
-- ---------------------------------------------------------------------------

insert into public.roles (code, name, description, display_order)
values
  ('cashier', 'Cashier', 'Point-of-sale and collections support.', 40),
  ('warehouse_staff', 'Warehouse Staff', 'Inventory and fulfilment operations.', 50),
  ('accountant', 'Accountant', 'Financial reporting and ledgers.', 60),
  ('administrator', 'Administrator', 'Technical administration.', 70)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- employee_assignments (future-ready)
-- ---------------------------------------------------------------------------

create table if not exists public.employee_assignments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  employee_id uuid not null references public.employees (id) on delete cascade,
  assignment_type text not null,
  target_id uuid,
  target_label text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint employee_assignments_type_allowed check (
    assignment_type in (
      'customer',
      'territory',
      'route',
      'product_category'
    )
  )
);

create index if not exists employee_assignments_employee_idx
  on public.employee_assignments (employee_id)
  where deleted_at is null;

create index if not exists employee_assignments_company_type_idx
  on public.employee_assignments (company_id, assignment_type)
  where deleted_at is null;

drop trigger if exists trg_employee_assignments_set_updated_at
  on public.employee_assignments;
create trigger trg_employee_assignments_set_updated_at
before update on public.employee_assignments
for each row execute function public.set_updated_at();

comment on table public.employee_assignments is
  'Future assignments: customers, territories, routes, product categories.';

-- ---------------------------------------------------------------------------
-- employee_activity_events
-- ---------------------------------------------------------------------------

create table if not exists public.employee_activity_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  employee_id uuid not null references public.employees (id) on delete cascade,
  event_type text not null,
  summary text not null,
  reference_type text,
  reference_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),

  constraint employee_activity_summary_not_blank
    check (length(trim(summary)) > 0),
  constraint employee_activity_event_type_not_blank
    check (length(trim(event_type)) > 0)
);

create index if not exists employee_activity_employee_created_idx
  on public.employee_activity_events (employee_id, created_at desc);

create index if not exists employee_activity_company_created_idx
  on public.employee_activity_events (company_id, created_at desc);

comment on table public.employee_activity_events is
  'Append-only employee activity for profiles and future reports.';

create or replace function public.log_employee_activity(
  p_employee_id uuid,
  p_event_type text,
  p_summary text,
  p_reference_type text default null,
  p_reference_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
  event_id uuid;
begin
  if company is null then
    raise exception 'Session context missing.';
  end if;

  insert into public.employee_activity_events (
    company_id,
    employee_id,
    event_type,
    summary,
    reference_type,
    reference_id
  )
  values (
    company,
    p_employee_id,
    p_event_type,
    trim(p_summary),
    p_reference_type,
    p_reference_id
  )
  returning id into event_id;

  update public.employees
  set last_active_at = timezone('utc', now())
  where id = p_employee_id
    and company_id = company;

  return event_id;
end;
$$;

revoke all on function public.log_employee_activity(uuid, text, text, text, uuid)
  from public;
grant execute on function public.log_employee_activity(uuid, text, text, text, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- RLS — company-scoped directory (session helpers are security definer)
-- ---------------------------------------------------------------------------

alter table public.employees enable row level security;

drop policy if exists "employees_select_own" on public.employees;
drop policy if exists "employees_select_own_company" on public.employees;
create policy "employees_select_own_company"
  on public.employees
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or (
      company_id = public.current_company_id()
      and deleted_at is null
    )
  );

drop policy if exists "employees_insert_own_company" on public.employees;
create policy "employees_insert_own_company"
  on public.employees
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

drop policy if exists "employees_update_own_company" on public.employees;
create policy "employees_update_own_company"
  on public.employees
  for update
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  )
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );

alter table public.employee_assignments enable row level security;
alter table public.employee_activity_events enable row level security;

drop policy if exists "employee_assignments_select_own_company"
  on public.employee_assignments;
create policy "employee_assignments_select_own_company"
  on public.employee_assignments
  for select
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

drop policy if exists "employee_assignments_write_own_company"
  on public.employee_assignments;
create policy "employee_assignments_write_own_company"
  on public.employee_assignments
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
  );

drop policy if exists "employee_activity_select_own_company"
  on public.employee_activity_events;
create policy "employee_activity_select_own_company"
  on public.employee_activity_events
  for select
  to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "employee_activity_insert_own_company"
  on public.employee_activity_events;
create policy "employee_activity_insert_own_company"
  on public.employee_activity_events
  for insert
  to authenticated
  with check (company_id = public.current_company_id());

-- ---------------------------------------------------------------------------
-- Storage — employee-avatars
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'employee-avatars',
  'employee-avatars',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "employee_avatars_select_own_company" on storage.objects;
create policy "employee_avatars_select_own_company"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'employee-avatars'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

drop policy if exists "employee_avatars_insert_own_company" on storage.objects;
create policy "employee_avatars_insert_own_company"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'employee-avatars'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

drop policy if exists "employee_avatars_update_own_company" on storage.objects;
create policy "employee_avatars_update_own_company"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'employee-avatars'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

drop policy if exists "employee_avatars_delete_own_company" on storage.objects;
create policy "employee_avatars_delete_own_company"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'employee-avatars'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );
