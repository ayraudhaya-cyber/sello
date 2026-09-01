-- =============================================================================
-- 029 — IAM permissions verbs + audit foundation
--
-- Extends role_module_access with CRUD/approve verbs and adds audit_events.
-- App continues to resolve defaults from RolePermissionProfile; DB overrides
-- and has_module_permission() prepare custom roles / RLS tightening later.
-- =============================================================================

-- Verb columns (legacy can_view / can_manage retained).
alter table public.role_module_access
  add column if not exists can_create boolean not null default false;

alter table public.role_module_access
  add column if not exists can_edit boolean not null default false;

alter table public.role_module_access
  add column if not exists can_delete boolean not null default false;

alter table public.role_module_access
  add column if not exists can_approve boolean not null default false;

comment on column public.role_module_access.can_manage is
  'Legacy aggregate write flag. Prefer can_create / can_edit / can_delete / can_approve.';

-- Expand manage into granular verbs when verbs were never set.
update public.role_module_access
set
  can_create = coalesce(can_create, false) or can_manage,
  can_edit = coalesce(can_edit, false) or can_manage,
  can_delete = coalesce(can_delete, false) or can_manage
where can_manage = true;

-- Current role helpers for future RLS policies.
create or replace function public.current_role_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select e.role_id
  from public.employees e
  where e.user_id = auth.uid()
    and e.deleted_at is null
    and e.is_active = true
  limit 1;
$$;

create or replace function public.current_role_code()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select r.code
  from public.employees e
  join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid()
    and e.deleted_at is null
    and e.is_active = true
  limit 1;
$$;

-- Permission check — company override wins over global role defaults.
create or replace function public.has_module_permission(
  p_module_key text,
  p_action text default 'view'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role_id uuid := public.current_role_id();
  v_company_id uuid := public.current_company_id();
  v_row public.role_module_access%rowtype;
  v_action text := lower(trim(p_action));
begin
  if v_role_id is null then
    return false;
  end if;

  -- Company-scoped override first.
  select *
  into v_row
  from public.role_module_access
  where role_id = v_role_id
    and module_key = p_module_key
    and company_id = v_company_id
  limit 1;

  if not found then
    select *
    into v_row
    from public.role_module_access
    where role_id = v_role_id
      and module_key = p_module_key
      and company_id is null
    limit 1;
  end if;

  -- No DB row → fall through: app RolePermissionProfile is source of truth.
  -- SQL policies may call this later once rows are seeded.
  if not found then
    return true;
  end if;

  return case v_action
    when 'view' then v_row.can_view
    when 'create' then v_row.can_create or v_row.can_manage
    when 'edit' then v_row.can_edit or v_row.can_manage
    when 'delete' then v_row.can_delete or v_row.can_manage
    when 'approve' then v_row.can_approve
    when 'manage' then v_row.can_manage
      or v_row.can_create or v_row.can_edit or v_row.can_delete
    else false
  end;
end;
$$;

comment on function public.has_module_permission(text, text) is
  'IAM helper for future RLS. Missing rows defer to app RolePermissionProfile.';

-- ---------------------------------------------------------------------------
-- Audit events — compliance / troubleshooting foundation
-- ---------------------------------------------------------------------------
create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  actor_employee_id uuid references public.employees (id) on delete set null,
  actor_name text,
  action text not null,
  summary text not null,
  module_key text,
  reference_type text,
  reference_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),

  constraint audit_events_action_not_blank
    check (length(trim(action)) > 0),
  constraint audit_events_summary_not_blank
    check (length(trim(summary)) > 0)
);

create index if not exists audit_events_company_created_idx
  on public.audit_events (company_id, created_at desc);

create index if not exists audit_events_module_idx
  on public.audit_events (company_id, module_key, created_at desc);

create index if not exists audit_events_reference_idx
  on public.audit_events (reference_type, reference_id);

comment on table public.audit_events is
  'Shared audit foundation. BusinessEventBus / AuditService write here.';

alter table public.audit_events enable row level security;

drop policy if exists "audit_events_select_own_company"
  on public.audit_events;
create policy "audit_events_select_own_company"
  on public.audit_events
  for select
  to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "audit_events_insert_own_company"
  on public.audit_events;
create policy "audit_events_insert_own_company"
  on public.audit_events
  for insert
  to authenticated
  with check (company_id = public.current_company_id());

create or replace function public.log_audit_event(
  p_company_id uuid,
  p_action text,
  p_summary text,
  p_actor_employee_id uuid default null,
  p_actor_name text default null,
  p_module_key text default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.audit_events (
    company_id,
    actor_employee_id,
    actor_name,
    action,
    summary,
    module_key,
    reference_type,
    reference_id,
    metadata
  ) values (
    p_company_id,
    coalesce(p_actor_employee_id, public.current_employee_id()),
    p_actor_name,
    trim(p_action),
    trim(p_summary),
    nullif(trim(p_module_key), ''),
    nullif(trim(p_reference_type), ''),
    p_reference_id,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.log_audit_event(
  uuid, text, text, uuid, text, text, text, uuid, jsonb
) from public;
grant execute on function public.log_audit_event(
  uuid, text, text, uuid, text, text, text, uuid, jsonb
) to authenticated;

-- Future: device registration for trusted devices / push / SSO endpoints.
create table if not exists public.device_registrations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  device_label text not null,
  platform text,
  push_token text,
  last_seen_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz,

  constraint device_registrations_label_not_blank
    check (length(trim(device_label)) > 0)
);

create index if not exists device_registrations_employee_idx
  on public.device_registrations (employee_id)
  where revoked_at is null;

comment on table public.device_registrations is
  'Future IAM seam for device trust, push, and SSO session binding.';

alter table public.device_registrations enable row level security;

drop policy if exists "device_registrations_own"
  on public.device_registrations;
create policy "device_registrations_own"
  on public.device_registrations
  for all
  to authenticated
  using (
    company_id = public.current_company_id()
    and employee_id = public.current_employee_id()
  )
  with check (
    company_id = public.current_company_id()
    and employee_id = public.current_employee_id()
  );
