-- =============================================================================
-- 026 — Customer Visits (operational field activity)
--
-- Schedule (023) = planned work.
-- Customer Visits = what actually happened.
-- GPS: one capture at Start, one at Complete (no continuous tracking).
-- =============================================================================

create table if not exists public.customer_visits (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid references public.branches (id) on delete set null,
  customer_id uuid not null references public.customers (id) on delete restrict,
  employee_id uuid not null references public.employees (id) on delete restrict,
  scheduled_visit_id uuid references public.scheduled_visits (id) on delete set null,

  status text not null default 'in_progress',
  outcome text,
  notes text,

  started_at timestamptz not null default timezone('utc', now()),
  ended_at timestamptz,
  duration_minutes integer,

  -- Proof of presence (point-in-time only)
  start_latitude double precision,
  start_longitude double precision,
  start_accuracy_meters double precision,
  end_latitude double precision,
  end_longitude double precision,
  end_accuracy_meters double precision,

  -- Future-ready seams (not fully implemented in app V1)
  signature_storage_path text,
  photo_paths jsonb not null default '[]'::jsonb,
  voice_note_path text,
  offline_client_id text,
  ai_summary text,
  follow_up_suggested_at timestamptz,

  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint customer_visits_status_allowed check (
    status in ('in_progress', 'completed', 'cancelled')
  ),
  constraint customer_visits_outcome_allowed check (
    outcome is null or outcome in (
      'order_created',
      'payment_collected',
      'follow_up_required',
      'customer_unavailable',
      'no_order_today',
      'new_sales_opportunity'
    )
  ),
  constraint customer_visits_notes_not_blank check (
    notes is null or length(trim(notes)) > 0
  ),
  constraint customer_visits_duration_non_negative check (
    duration_minutes is null or duration_minutes >= 0
  ),
  constraint customer_visits_ended_after_start check (
    ended_at is null or ended_at >= started_at
  ),
  constraint customer_visits_photo_paths_is_array check (
    jsonb_typeof(photo_paths) = 'array'
  )
);

comment on table public.customer_visits is
  'Operational field visits — actual customer interactions (separate from schedule plan).';
comment on column public.customer_visits.scheduled_visit_id is
  'Optional link to the planned scheduled_visits row this visit fulfilled.';
comment on column public.customer_visits.outcome is
  'Extensible outcome vocabulary — add values via migration when needed.';
comment on column public.customer_visits.signature_storage_path is
  'Future customer signature evidence.';
comment on column public.customer_visits.photo_paths is
  'Future photo evidence paths (json array).';
comment on column public.customer_visits.voice_note_path is
  'Future voice note storage path.';
comment on column public.customer_visits.offline_client_id is
  'Future offline visit logging client id.';
comment on column public.customer_visits.ai_summary is
  'Future AI visit summary.';

create index if not exists customer_visits_company_started_idx
  on public.customer_visits (company_id, started_at desc)
  where deleted_at is null;

create index if not exists customer_visits_employee_started_idx
  on public.customer_visits (employee_id, started_at desc)
  where deleted_at is null;

create index if not exists customer_visits_customer_started_idx
  on public.customer_visits (customer_id, started_at desc)
  where deleted_at is null;

create index if not exists customer_visits_company_status_idx
  on public.customer_visits (company_id, status)
  where deleted_at is null;

create index if not exists customer_visits_scheduled_visit_idx
  on public.customer_visits (scheduled_visit_id)
  where scheduled_visit_id is not null and deleted_at is null;

-- One active visit per employee
create unique index if not exists customer_visits_one_active_per_employee
  on public.customer_visits (company_id, employee_id)
  where status = 'in_progress' and deleted_at is null;

create unique index if not exists customer_visits_company_offline_client_id_key
  on public.customer_visits (company_id, offline_client_id)
  where offline_client_id is not null and deleted_at is null;

drop trigger if exists trg_customer_visits_set_updated_at
  on public.customer_visits;
create trigger trg_customer_visits_set_updated_at
before update on public.customer_visits
for each row execute function public.set_updated_at();

create or replace function public.validate_customer_visit_tenant_scope()
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
    raise exception 'customer_visits.customer_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.employees e
    where e.id = new.employee_id
      and e.company_id = new.company_id
      and e.deleted_at is null
  ) then
    raise exception 'customer_visits.employee_id must belong to the same company';
  end if;

  if new.branch_id is not null and not exists (
    select 1 from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'customer_visits.branch_id must belong to the same company';
  end if;

  if new.scheduled_visit_id is not null and not exists (
    select 1 from public.scheduled_visits sv
    where sv.id = new.scheduled_visit_id
      and sv.company_id = new.company_id
      and sv.deleted_at is null
  ) then
    raise exception 'customer_visits.scheduled_visit_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_customer_visits_validate_tenant_scope
  on public.customer_visits;
create trigger trg_customer_visits_validate_tenant_scope
before insert or update of company_id, customer_id, employee_id, branch_id, scheduled_visit_id
on public.customer_visits
for each row execute function public.validate_customer_visit_tenant_scope();

alter table public.customer_visits enable row level security;

drop policy if exists "customer_visits_select_own_company"
  on public.customer_visits;
create policy "customer_visits_select_own_company"
  on public.customer_visits
  for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  );

drop policy if exists "customer_visits_insert_own_company"
  on public.customer_visits;
create policy "customer_visits_insert_own_company"
  on public.customer_visits
  for insert
  to authenticated
  with check (company_id = public.current_company_id());

drop policy if exists "customer_visits_update_own_company"
  on public.customer_visits;
create policy "customer_visits_update_own_company"
  on public.customer_visits
  for update
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  )
  with check (company_id = public.current_company_id());

-- Link orders / payments to operational visits
alter table public.orders
  drop constraint if exists orders_visit_id_fkey;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_visit_id_fkey'
  ) then
    alter table public.orders
      add constraint orders_visit_id_fkey
      foreign key (visit_id) references public.customer_visits (id)
      on delete set null;
  end if;
end $$;

comment on column public.orders.visit_id is
  'Optional link to the customer_visits row during which this order was created.';

alter table public.payments
  add column if not exists visit_id uuid references public.customer_visits (id) on delete set null;

comment on column public.payments.visit_id is
  'Optional link to the customer_visits row during which this payment was collected.';

create index if not exists payments_visit_id_idx
  on public.payments (visit_id)
  where visit_id is not null and deleted_at is null;

create index if not exists orders_visit_id_idx
  on public.orders (visit_id)
  where visit_id is not null and deleted_at is null;

-- last_visit_at now driven by operational customer_visits
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
  select max(v.ended_at)
  into last_completed
  from public.customer_visits v
  where v.customer_id = cid
    and v.deleted_at is null
    and v.status = 'completed';

  -- Fallback to legacy scheduled completion markers if no operational visits yet
  if last_completed is null then
    select max(sv.completed_at)
    into last_completed
    from public.scheduled_visits sv
    where sv.customer_id = cid
      and sv.deleted_at is null
      and sv.status = 'completed';
  end if;

  select min(sv.visit_date)
  into next_scheduled
  from public.scheduled_visits sv
  where sv.customer_id = cid
    and sv.deleted_at is null
    and sv.status = 'scheduled'
    and sv.visit_date >= (timezone('utc', now()))::date;

  update public.customers
  set
    last_visit_at = last_completed,
    next_visit_at = next_scheduled,
    updated_at = timezone('utc', now())
  where id = cid;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_customer_visits_sync_customer_markers
  on public.customer_visits;
create trigger trg_customer_visits_sync_customer_markers
after insert or update of status, ended_at, deleted_at, customer_id
or delete
on public.customer_visits
for each row execute function public.sync_customer_visit_markers();

-- receive_payment: optional visit association (new overload; drop prior arity)
drop function if exists public.receive_payment(uuid, numeric, text, jsonb, text, text);

create or replace function public.receive_payment(
  p_customer_id uuid,
  p_amount numeric,
  p_method text,
  p_allocations jsonb default '[]'::jsonb,
  p_reference text default null,
  p_notes text default null,
  p_visit_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  branch uuid;
  payment_id uuid;
  payment_no text;
  alloc jsonb;
  alloc_order uuid;
  alloc_amount numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  customer_row public.customers%rowtype;
  order_row public.orders%rowtype;
  already_paid numeric(14, 2);
  remaining numeric(14, 2);
  ar_reduction numeric(14, 2);
  overpay numeric(14, 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  if p_method not in ('cash', 'card', 'bank_transfer', 'wallet', 'credit_settlement') then
    raise exception 'Unsupported payment method.';
  end if;

  if p_visit_id is not null and not exists (
    select 1 from public.customer_visits cv
    where cv.id = p_visit_id
      and cv.company_id = company
      and cv.customer_id = p_customer_id
      and cv.deleted_at is null
  ) then
    raise exception 'Visit not found for this customer.';
  end if;

  select * into customer_row
  from public.customers
  where id = p_customer_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Customer not found.';
  end if;

  select e.branch_id into branch
  from public.employees e
  where e.id = emp
    and e.company_id = company
    and e.deleted_at is null;

  if branch is null then
    select b.id into branch
    from public.branches b
    where b.company_id = company
      and b.deleted_at is null
      and b.is_active = true
    order by b.created_at
    limit 1;
  end if;

  if branch is null then
    raise exception 'No branch available for this payment.';
  end if;

  if p_method = 'wallet' and customer_row.wallet_balance < p_amount then
    raise exception 'Insufficient wallet balance.';
  end if;

  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_order := (alloc->>'order_id')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    if alloc_amount is null or alloc_amount <= 0 then
      raise exception 'Allocation amount must be positive.';
    end if;

    select * into order_row
    from public.orders
    where id = alloc_order
      and company_id = company
      and customer_id = p_customer_id
      and deleted_at is null
      and status = 'completed';

    if not found then
      raise exception 'Allocation order is not a completed order for this customer.';
    end if;

    select coalesce(sum(pa.amount), 0)
      into already_paid
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = alloc_order
      and p.deleted_at is null
      and p.status = 'completed';

    remaining := order_row.total - already_paid;
    if alloc_amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on order %', order_row.order_number;
    end if;

    alloc_total := alloc_total + alloc_amount;
  end loop;

  if alloc_total > p_amount + 0.001 then
    raise exception 'Allocations exceed payment amount.';
  end if;

  payment_no := public.next_payment_number(company);

  insert into public.payments (
    company_id,
    branch_id,
    customer_id,
    employee_id,
    payment_number,
    amount,
    method,
    status,
    reference,
    notes,
    visit_id,
    created_by,
    updated_by
  )
  values (
    company,
    branch,
    p_customer_id,
    emp,
    payment_no,
    p_amount,
    p_method,
    'completed',
    nullif(trim(coalesce(p_reference, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    p_visit_id,
    emp,
    emp
  )
  returning id into payment_id;

  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_order := (alloc->>'order_id')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    insert into public.payment_allocations (
      company_id,
      payment_id,
      order_id,
      amount,
      created_by,
      updated_by
    )
    values (
      company,
      payment_id,
      alloc_order,
      alloc_amount,
      emp,
      emp
    );

    perform public.refresh_order_payment_status(alloc_order);
  end loop;

  -- Apply to customer financial profile (same rules as 012)
  ar_reduction := least(p_amount, customer_row.current_balance);
  overpay := greatest(p_amount - alloc_total, 0);

  if p_method = 'wallet' then
    update public.customers
    set
      wallet_balance = wallet_balance - p_amount,
      current_balance = greatest(current_balance - alloc_total, 0),
      updated_by = emp
    where id = p_customer_id;
  else
    update public.customers
    set
      current_balance = greatest(current_balance - ar_reduction, 0),
      wallet_balance = wallet_balance + overpay,
      updated_by = emp
    where id = p_customer_id;
  end if;

  return payment_id;
end;
$$;

revoke all on function public.receive_payment(uuid, numeric, text, jsonb, text, text, uuid) from public;
grant execute on function public.receive_payment(uuid, numeric, text, jsonb, text, text, uuid) to authenticated;
