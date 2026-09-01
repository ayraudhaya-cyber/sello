-- =============================================================================
-- 024 — Notifications & activity center foundation
--
-- Central in-app inbox + company activity feed. External channels
-- (push / email / SMS / WhatsApp) are reserved via preferences only.
-- Employee profile audit remains on employee_activity_events (014).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- In-app notifications (per-recipient inbox)
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  recipient_employee_id uuid not null references public.employees (id) on delete cascade,
  actor_employee_id uuid references public.employees (id) on delete set null,
  category text not null,
  type text not null,
  priority text not null default 'normal',
  title text not null,
  body text,
  reference_type text,
  reference_id uuid,
  route_hint text,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint notifications_category_allowed check (
    category in (
      'orders', 'inventory', 'payments', 'customers',
      'schedule', 'visits', 'team', 'system', 'intelligence'
    )
  ),
  constraint notifications_priority_allowed check (
    priority in ('critical', 'high', 'normal', 'information')
  ),
  constraint notifications_title_not_blank check (length(trim(title)) > 0),
  constraint notifications_type_not_blank check (length(trim(type)) > 0),
  constraint notifications_body_not_blank check (
    body is null or length(trim(body)) > 0
  ),
  constraint notifications_route_hint_not_blank check (
    route_hint is null or length(trim(route_hint)) > 0
  )
);

create index if not exists notifications_recipient_created_idx
  on public.notifications (recipient_employee_id, created_at desc)
  where deleted_at is null;

create index if not exists notifications_recipient_unread_idx
  on public.notifications (recipient_employee_id)
  where deleted_at is null and read_at is null and archived_at is null;

create index if not exists notifications_company_created_idx
  on public.notifications (company_id, created_at desc)
  where deleted_at is null;

comment on table public.notifications is
  'In-app notification inbox. One row per recipient. Push/email later.';
comment on column public.notifications.route_hint is
  'Optional deep-link path (e.g. /hub/orders). Client may also resolve from reference.';
comment on column public.notifications.archived_at is
  'Future archive support. Null in V1 UI.';

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own"
  on public.notifications;
create policy "notifications_select_own"
  on public.notifications
  for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and recipient_employee_id = public.current_employee_id()
    and deleted_at is null
  );

drop policy if exists "notifications_update_own"
  on public.notifications;
create policy "notifications_update_own"
  on public.notifications
  for update
  to authenticated
  using (
    company_id = public.current_company_id()
    and recipient_employee_id = public.current_employee_id()
    and deleted_at is null
  )
  with check (
    company_id = public.current_company_id()
    and recipient_employee_id = public.current_employee_id()
  );

-- Inserts go through security-definer RPC (emit_notification).

-- ---------------------------------------------------------------------------
-- Company activity feed (operational history — not an inbox)
-- ---------------------------------------------------------------------------
create table if not exists public.company_activity_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  actor_employee_id uuid references public.employees (id) on delete set null,
  actor_name text,
  category text not null,
  event_type text not null,
  summary text not null,
  reference_type text,
  reference_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),

  constraint company_activity_category_allowed check (
    category in (
      'orders', 'inventory', 'payments', 'customers',
      'schedule', 'visits', 'team', 'system', 'intelligence'
    )
  ),
  constraint company_activity_summary_not_blank check (length(trim(summary)) > 0),
  constraint company_activity_event_type_not_blank check (
    length(trim(event_type)) > 0
  )
);

create index if not exists company_activity_company_created_idx
  on public.company_activity_events (company_id, created_at desc);

comment on table public.company_activity_events is
  'Business operational timeline. Distinct from employee_activity_events (HR audit).';

alter table public.company_activity_events enable row level security;

drop policy if exists "company_activity_select_own_company"
  on public.company_activity_events;
create policy "company_activity_select_own_company"
  on public.company_activity_events
  for select
  to authenticated
  using (company_id = public.current_company_id());

-- ---------------------------------------------------------------------------
-- Channel preferences (foundation — external delivery not implemented)
-- ---------------------------------------------------------------------------
create table if not exists public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  category text not null,
  channel_in_app boolean not null default true,
  channel_push boolean not null default false,
  channel_email boolean not null default false,
  channel_sms boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint notification_preferences_category_allowed check (
    category in (
      'orders', 'inventory', 'payments', 'customers',
      'schedule', 'visits', 'team', 'system', 'intelligence'
    )
  ),
  constraint notification_preferences_unique unique (employee_id, category)
);

create index if not exists notification_preferences_employee_idx
  on public.notification_preferences (employee_id);

comment on table public.notification_preferences is
  'Per-user channel toggles. Only in-app is honored in V1.';

drop trigger if exists trg_notification_preferences_set_updated_at
  on public.notification_preferences;
create trigger trg_notification_preferences_set_updated_at
before update on public.notification_preferences
for each row execute function public.set_updated_at();

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences_own"
  on public.notification_preferences;
create policy "notification_preferences_own"
  on public.notification_preferences
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

-- ---------------------------------------------------------------------------
-- Emit helpers (security definer — domains call via client RPC)
-- ---------------------------------------------------------------------------
create or replace function public.emit_notification(
  p_company_id uuid,
  p_recipient_employee_id uuid,
  p_category text,
  p_type text,
  p_title text,
  p_body text default null,
  p_priority text default 'normal',
  p_actor_employee_id uuid default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_route_hint text default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  prefer_in_app boolean := true;
begin
  if p_company_id is null or p_recipient_employee_id is null then
    raise exception 'company and recipient are required';
  end if;

  -- Honor in-app preference when a row exists; default allow.
  select coalesce(np.channel_in_app, true)
  into prefer_in_app
  from public.notification_preferences np
  where np.employee_id = p_recipient_employee_id
    and np.category = p_category
  limit 1;

  if prefer_in_app is false then
    return null;
  end if;

  insert into public.notifications (
    company_id,
    recipient_employee_id,
    actor_employee_id,
    category,
    type,
    priority,
    title,
    body,
    reference_type,
    reference_id,
    route_hint,
    payload
  ) values (
    p_company_id,
    p_recipient_employee_id,
    p_actor_employee_id,
    p_category,
    p_type,
    coalesce(nullif(trim(p_priority), ''), 'normal'),
    trim(p_title),
    nullif(trim(p_body), ''),
    p_reference_type,
    p_reference_id,
    nullif(trim(p_route_hint), ''),
    coalesce(p_payload, '{}'::jsonb)
  )
  returning id into new_id;

  return new_id;
end;
$$;

comment on function public.emit_notification is
  'Insert one in-app notification for a recipient. Returns null if in-app disabled.';

create or replace function public.emit_notifications_for_hub_roles(
  p_company_id uuid,
  p_category text,
  p_type text,
  p_title text,
  p_body text default null,
  p_priority text default 'normal',
  p_actor_employee_id uuid default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_route_hint text default null,
  p_payload jsonb default '{}'::jsonb,
  p_exclude_employee_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer := 0;
  rec record;
begin
  for rec in
    select e.id
    from public.employees e
    join public.roles r on r.id = e.role_id
    where e.company_id = p_company_id
      and e.deleted_at is null
      and e.employment_status = 'active'
      and r.code in ('owner', 'manager')
      and (p_exclude_employee_id is null or e.id <> p_exclude_employee_id)
  loop
    if public.emit_notification(
      p_company_id,
      rec.id,
      p_category,
      p_type,
      p_title,
      p_body,
      p_priority,
      p_actor_employee_id,
      p_reference_type,
      p_reference_id,
      p_route_hint,
      p_payload
    ) is not null then
      inserted := inserted + 1;
    end if;
  end loop;

  return inserted;
end;
$$;

comment on function public.emit_notifications_for_hub_roles is
  'Notify all active Owners/Managers in the company (Hub roles).';

create or replace function public.log_company_activity(
  p_company_id uuid,
  p_category text,
  p_event_type text,
  p_summary text,
  p_actor_employee_id uuid default null,
  p_actor_name text default null,
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
  new_id uuid;
  resolved_name text := nullif(trim(p_actor_name), '');
begin
  if p_company_id is null then
    raise exception 'company is required';
  end if;

  if resolved_name is null and p_actor_employee_id is not null then
    select e.full_name into resolved_name
    from public.employees e
    where e.id = p_actor_employee_id;
  end if;

  insert into public.company_activity_events (
    company_id,
    actor_employee_id,
    actor_name,
    category,
    event_type,
    summary,
    reference_type,
    reference_id,
    metadata
  ) values (
    p_company_id,
    p_actor_employee_id,
    resolved_name,
    p_category,
    trim(p_event_type),
    trim(p_summary),
    p_reference_type,
    p_reference_id,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into new_id;

  return new_id;
end;
$$;

comment on function public.log_company_activity is
  'Append a company-wide operational activity event.';

grant execute on function public.emit_notification(
  uuid, uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb
) to authenticated;

grant execute on function public.emit_notifications_for_hub_roles(
  uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb, uuid
) to authenticated;

grant execute on function public.log_company_activity(
  uuid, text, text, text, uuid, text, text, uuid, jsonb
) to authenticated;
