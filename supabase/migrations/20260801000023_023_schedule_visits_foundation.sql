-- =============================================================================
-- 023 — Schedule / customer visits foundation
--
-- Hub plans visits; Sales Home consumes today's assigned visits.
-- Recurrence columns are reserved (not fully implemented in app V1).
-- =============================================================================

create table if not exists public.scheduled_visits (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid references public.branches (id) on delete set null,
  customer_id uuid not null references public.customers (id) on delete restrict,
  employee_id uuid not null references public.employees (id) on delete restrict,
  visit_date date not null,
  preferred_time time,
  expected_duration_minutes integer,
  status text not null default 'scheduled',
  priority text not null default 'normal',
  purpose text,
  notes text,
  sort_order integer not null default 0,
  completed_at timestamptz,
  cancelled_at timestamptz,
  -- Recurrence foundation (V1 stores null; engine later)
  recurrence_rule text,
  recurrence_parent_id uuid references public.scheduled_visits (id) on delete set null,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint scheduled_visits_status_allowed check (
    status in ('scheduled', 'completed', 'missed', 'cancelled', 'unplanned')
  ),
  constraint scheduled_visits_priority_allowed check (
    priority in ('low', 'normal', 'high', 'urgent')
  ),
  constraint scheduled_visits_duration_positive check (
    expected_duration_minutes is null or expected_duration_minutes > 0
  ),
  constraint scheduled_visits_purpose_not_blank check (
    purpose is null or length(trim(purpose)) > 0
  ),
  constraint scheduled_visits_notes_not_blank check (
    notes is null or length(trim(notes)) > 0
  ),
  constraint scheduled_visits_recurrence_rule_not_blank check (
    recurrence_rule is null or length(trim(recurrence_rule)) > 0
  )
);

create index if not exists scheduled_visits_company_date_idx
  on public.scheduled_visits (company_id, visit_date)
  where deleted_at is null;

create index if not exists scheduled_visits_employee_date_idx
  on public.scheduled_visits (employee_id, visit_date)
  where deleted_at is null;

create index if not exists scheduled_visits_customer_date_idx
  on public.scheduled_visits (customer_id, visit_date)
  where deleted_at is null;

create index if not exists scheduled_visits_company_status_idx
  on public.scheduled_visits (company_id, status)
  where deleted_at is null;

drop trigger if exists trg_scheduled_visits_set_updated_at
  on public.scheduled_visits;
create trigger trg_scheduled_visits_set_updated_at
before update on public.scheduled_visits
for each row execute function public.set_updated_at();

create or replace function public.validate_scheduled_visit_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.customers c
    where c.id = new.customer_id
      and c.company_id = new.company_id
      and c.deleted_at is null
  ) then
    raise exception 'scheduled_visits.customer_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.employees e
    where e.id = new.employee_id
      and e.company_id = new.company_id
      and e.deleted_at is null
  ) then
    raise exception 'scheduled_visits.employee_id must belong to the same company';
  end if;

  if new.branch_id is not null and not exists (
    select 1 from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'scheduled_visits.branch_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_scheduled_visits_validate_tenant_scope
  on public.scheduled_visits;
create trigger trg_scheduled_visits_validate_tenant_scope
before insert or update of company_id, customer_id, employee_id, branch_id
on public.scheduled_visits
for each row execute function public.validate_scheduled_visit_tenant_scope();

comment on table public.scheduled_visits is
  'Customer visit plan — Hub schedules; Sales Home consumes today by employee.';
comment on column public.scheduled_visits.recurrence_rule is
  'Future RRULE / interval text. Null in V1.';
comment on column public.scheduled_visits.sort_order is
  'Day route order for the assigned rep (reorder UI later).';

alter table public.scheduled_visits enable row level security;

drop policy if exists "scheduled_visits_select_own_company"
  on public.scheduled_visits;
create policy "scheduled_visits_select_own_company"
  on public.scheduled_visits
  for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  );

drop policy if exists "scheduled_visits_insert_own_company"
  on public.scheduled_visits;
create policy "scheduled_visits_insert_own_company"
  on public.scheduled_visits
  for insert
  to authenticated
  with check (company_id = public.current_company_id());

drop policy if exists "scheduled_visits_update_own_company"
  on public.scheduled_visits;
create policy "scheduled_visits_update_own_company"
  on public.scheduled_visits
  for update
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  )
  with check (company_id = public.current_company_id());

-- Optional denormalized peek columns on customers (reports / profile).
alter table public.customers
  add column if not exists last_visit_at timestamptz;

alter table public.customers
  add column if not exists next_visit_at date;

comment on column public.customers.last_visit_at is
  'Last completed visit timestamp (maintained by visit completion).';
comment on column public.customers.next_visit_at is
  'Next scheduled visit date (maintained on schedule upsert).';

create or replace function public.sync_customer_visit_markers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(new.customer_id, old.customer_id);
  last_completed timestamptz;
  next_scheduled date;
begin
  select max(v.completed_at)
  into last_completed
  from public.scheduled_visits v
  where v.customer_id = cid
    and v.deleted_at is null
    and v.status = 'completed';

  select min(v.visit_date)
  into next_scheduled
  from public.scheduled_visits v
  where v.customer_id = cid
    and v.deleted_at is null
    and v.status = 'scheduled'
    and v.visit_date >= (timezone('utc', now()))::date;

  update public.customers
  set
    last_visit_at = last_completed,
    next_visit_at = next_scheduled,
    updated_at = timezone('utc', now())
  where id = cid;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_scheduled_visits_sync_customer_markers
  on public.scheduled_visits;
create trigger trg_scheduled_visits_sync_customer_markers
after insert or update of status, visit_date, completed_at, deleted_at, customer_id
or delete
on public.scheduled_visits
for each row execute function public.sync_customer_visit_markers();
