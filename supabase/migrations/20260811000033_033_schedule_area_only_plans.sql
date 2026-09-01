-- =============================================================================
-- Migration 033 — Area-only field plans
--
-- A plan is valid with customers, an area, or both.
-- Area-only rows are territory assignments — not fake customer stops.
-- =============================================================================

alter table public.scheduled_visits
  alter column customer_id drop not null;

alter table public.scheduled_visits
  drop constraint if exists scheduled_visits_scope_required;

alter table public.scheduled_visits
  add constraint scheduled_visits_scope_required
    check (
      customer_id is not null
      or (area is not null and length(trim(area)) > 0)
    );

create or replace function public.validate_scheduled_visit_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if new.customer_id is not null and not exists (
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
  if cid is null then
    return coalesce(new, old);
  end if;

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

comment on table public.scheduled_visits is
  'Field plan — Hub assigns a rep a day scope: customers, an area, or both. '
  'Sales Home consumes customer stops; area-only rows are territory assignments.';

comment on column public.scheduled_visits.customer_id is
  'Optional when area is set. Null means a territory/area assignment, not a customer stop.';
