-- =============================================================================
-- Migration 065 — Cheque management foundation
--
-- Separate cheque instrument with lifecycle. Balance effect:
--   awaiting_collection → no AR change
--   collected           → create one completed payments row (method=cheque) once
--   deposited / cleared → status only (no second payment)
--   bounced / cancelled after apply → reverse AR/wallet once (idempotent)
--
-- Reuses payments + payment_allocations ledger. Does not invent a parallel ledger.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extend payments.method allow-list with cheque
-- ---------------------------------------------------------------------------

alter table public.payments
  drop constraint if exists payments_method_allowed;

alter table public.payments
  add constraint payments_method_allowed check (
    method in (
      'cash',
      'card',
      'bank_transfer',
      'wallet',
      'credit_settlement',
      'cheque'
    )
  );

comment on column public.payments.method is
  'cash | card | bank_transfer | wallet | credit_settlement | cheque';

-- Block public receive_payment from accepting cheque (cheque RPCs only).
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
  approval_required boolean := false;
  payment_status text := 'completed';
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

  select coalesce(cs.collection_approval_required, false)
    into approval_required
  from public.company_settings cs
  where cs.company_id = company
  limit 1;

  if approval_required and not public.can_auto_apply_collections() then
    payment_status := 'pending';
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
      and status in ('placed', 'partially_delivered', 'completed');

    if not found then
      raise exception
        'Allocation order must be a placed, partially delivered, or completed order for this customer.';
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
    payment_status,
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
  end loop;

  if payment_status = 'completed' then
    perform public.apply_payment_financials(payment_id);
  end if;

  return payment_id;
end;
$$;

revoke all on function public.receive_payment(uuid, numeric, text, jsonb, text, text, uuid)
  from public;
grant execute on function public.receive_payment(uuid, numeric, text, jsonb, text, text, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- cheques table
-- ---------------------------------------------------------------------------

create table if not exists public.cheques (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete restrict,
  employee_id uuid not null references public.employees (id) on delete restrict,
  cheque_number_label text not null,
  amount numeric(14, 2) not null,
  bank_name text not null,
  cheque_number text not null,
  holder_name text not null,
  cheque_date date not null,
  collection_date date,
  photo_path text,
  notes text,
  status text not null default 'awaiting_collection',
  visit_id uuid references public.customer_visits (id) on delete set null,
  payment_id uuid references public.payments (id) on delete set null,
  -- Snapshot of AR/wallet effect at collect time (for exact one-time reverse)
  applied_ar_amount numeric(14, 2) not null default 0,
  applied_wallet_amount numeric(14, 2) not null default 0,
  balance_applied_at timestamptz,
  balance_reversed_at timestamptz,
  collected_at timestamptz,
  deposited_at timestamptz,
  cleared_at timestamptz,
  bounced_at timestamptz,
  cancelled_at timestamptz,
  collected_by uuid references public.employees (id) on delete set null,
  deposited_by uuid references public.employees (id) on delete set null,
  cleared_by uuid references public.employees (id) on delete set null,
  bounced_by uuid references public.employees (id) on delete set null,
  cancelled_by uuid references public.employees (id) on delete set null,
  bounce_reason text,
  cancel_reason text,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint cheques_amount_positive check (amount > 0),
  constraint cheques_bank_name_not_blank check (length(trim(bank_name)) > 0),
  constraint cheques_cheque_number_not_blank check (length(trim(cheque_number)) > 0),
  constraint cheques_holder_name_not_blank check (length(trim(holder_name)) > 0),
  constraint cheques_label_not_blank check (length(trim(cheque_number_label)) > 0),
  constraint cheques_notes_not_blank
    check (notes is null or length(trim(notes)) > 0),
  constraint cheques_photo_path_not_blank
    check (photo_path is null or length(trim(photo_path)) > 0),
  constraint cheques_status_allowed check (
    status in (
      'awaiting_collection',
      'collected',
      'deposited',
      'cleared',
      'bounced',
      'cancelled'
    )
  ),
  constraint cheques_applied_ar_non_negative check (applied_ar_amount >= 0),
  constraint cheques_applied_wallet_non_negative check (applied_wallet_amount >= 0),
  constraint cheques_collection_date_when_collected check (
    status = 'awaiting_collection'
    or collection_date is not null
    or status in ('cancelled')
  )
);

create unique index if not exists cheques_company_label_active_key
  on public.cheques (company_id, cheque_number_label)
  where deleted_at is null;

create unique index if not exists cheques_payment_id_key
  on public.cheques (payment_id)
  where payment_id is not null and deleted_at is null;

create index if not exists cheques_company_status_idx
  on public.cheques (company_id, status)
  where deleted_at is null;

create index if not exists cheques_company_customer_idx
  on public.cheques (company_id, customer_id)
  where deleted_at is null;

create index if not exists cheques_company_cheque_date_idx
  on public.cheques (company_id, cheque_date)
  where deleted_at is null;

create index if not exists cheques_company_collection_date_idx
  on public.cheques (company_id, collection_date)
  where deleted_at is null and collection_date is not null;

create index if not exists cheques_company_bank_idx
  on public.cheques (company_id, bank_name)
  where deleted_at is null;

create index if not exists cheques_company_created_at_idx
  on public.cheques (company_id, created_at desc)
  where deleted_at is null;

create trigger trg_cheques_set_updated_at
before update on public.cheques
for each row execute function public.set_updated_at();

create or replace function public.validate_cheque_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'cheques.branch_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = new.customer_id
      and c.company_id = new.company_id
      and c.deleted_at is null
  ) then
    raise exception 'cheques.customer_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.employees e
    where e.id = new.employee_id
      and e.company_id = new.company_id
      and e.deleted_at is null
  ) then
    raise exception 'cheques.employee_id must belong to the same company';
  end if;

  if new.visit_id is not null and not exists (
    select 1 from public.customer_visits cv
    where cv.id = new.visit_id
      and cv.company_id = new.company_id
      and cv.customer_id = new.customer_id
      and cv.deleted_at is null
  ) then
    raise exception 'cheques.visit_id must belong to the same company and customer';
  end if;

  if new.payment_id is not null and not exists (
    select 1 from public.payments p
    where p.id = new.payment_id
      and p.company_id = new.company_id
      and p.deleted_at is null
  ) then
    raise exception 'cheques.payment_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_cheques_validate_tenant_scope on public.cheques;
create trigger trg_cheques_validate_tenant_scope
before insert or update of company_id, branch_id, customer_id, employee_id, visit_id, payment_id
on public.cheques
for each row execute function public.validate_cheque_tenant_scope();

comment on table public.cheques is
  'Cheque instruments. AR reduces once on collect via linked payments row; deposit/clear are status-only; bounce/cancel reverse once.';

-- ---------------------------------------------------------------------------
-- cheque_status_events (audit trail)
-- ---------------------------------------------------------------------------

create table if not exists public.cheque_status_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  cheque_id uuid not null references public.cheques (id) on delete cascade,
  from_status text,
  to_status text not null,
  actor_employee_id uuid references public.employees (id) on delete set null,
  note text,
  created_at timestamptz not null default timezone('utc', now()),

  constraint cheque_status_events_to_status_allowed check (
    to_status in (
      'awaiting_collection',
      'collected',
      'deposited',
      'cleared',
      'bounced',
      'cancelled'
    )
  )
);

create index if not exists cheque_status_events_cheque_id_idx
  on public.cheque_status_events (cheque_id, created_at);

alter table public.cheques enable row level security;
alter table public.cheque_status_events enable row level security;

create policy "cheques_select_own_company"
  on public.cheques
  for select
  to authenticated
  using (
    deleted_at is null
    and company_id = public.current_company_id()
  );

create policy "cheques_insert_own_company"
  on public.cheques
  for insert
  to authenticated
  with check (company_id = public.current_company_id());

create policy "cheques_update_own_company"
  on public.cheques
  for update
  to authenticated
  using (
    deleted_at is null
    and company_id = public.current_company_id()
  )
  with check (company_id = public.current_company_id());

create policy "cheque_status_events_select_own_company"
  on public.cheque_status_events
  for select
  to authenticated
  using (company_id = public.current_company_id());

create policy "cheque_status_events_insert_own_company"
  on public.cheque_status_events
  for insert
  to authenticated
  with check (company_id = public.current_company_id());

revoke all on table public.cheques from public;
grant select, insert, update on table public.cheques to authenticated;

revoke all on table public.cheque_status_events from public;
grant select, insert on table public.cheque_status_events to authenticated;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.can_manage_cheque_clearance()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  -- employees.role_id → roles.code (same pattern as can_auto_apply_collections)
  select coalesce(public.current_role_code(), '') in (
    'owner',
    'administrator',
    'manager'
  );
$$;

revoke all on function public.can_manage_cheque_clearance() from public;
grant execute on function public.can_manage_cheque_clearance() to authenticated;

create or replace function public.next_cheque_number(p_company_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  day_key text := to_char(timezone('utc', now()), 'YYYYMMDD');
  seq int;
begin
  select coalesce(max(
    nullif(substring(cheque_number_label from 'CHEQ-' || day_key || '-([0-9]+)$'), '')::int
  ), 0) + 1
  into seq
  from public.cheques
  where company_id = p_company_id
    and cheque_number_label like 'CHEQ-' || day_key || '-%';

  return 'CHEQ-' || day_key || '-' || lpad(seq::text, 4, '0');
end;
$$;

revoke all on function public.next_cheque_number(uuid) from public;
grant execute on function public.next_cheque_number(uuid) to authenticated;

create or replace function public._log_cheque_status(
  p_cheque_id uuid,
  p_company_id uuid,
  p_from text,
  p_to text,
  p_actor uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.cheque_status_events (
    company_id,
    cheque_id,
    from_status,
    to_status,
    actor_employee_id,
    note
  )
  values (
    p_company_id,
    p_cheque_id,
    p_from,
    p_to,
    p_actor,
    nullif(trim(coalesce(p_note, '')), '')
  );
end;
$$;

-- Reverse ledger once (bounce / cancel after collect).
create or replace function public._reverse_cheque_collection_ledger(
  p_cheque_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
  alloc_row public.payment_allocations%rowtype;
begin
  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  -- Idempotent
  if ch.balance_reversed_at is not null then
    return;
  end if;

  if ch.balance_applied_at is null or ch.payment_id is null then
    return;
  end if;

  update public.customers
  set
    current_balance = current_balance + coalesce(ch.applied_ar_amount, 0),
    wallet_balance = greatest(
      wallet_balance - coalesce(ch.applied_wallet_amount, 0),
      0
    ),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = ch.customer_id
    and company_id = company
    and deleted_at is null;

  update public.payments
  set
    status = 'refunded',
    refunded_at = timezone('utc', now()),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = ch.payment_id
    and company_id = company
    and deleted_at is null
    and status = 'completed';

  for alloc_row in
    select *
    from public.payment_allocations
    where payment_id = ch.payment_id
  loop
    perform public.refresh_order_payment_status(alloc_row.order_id);
  end loop;

  update public.cheques
  set
    balance_reversed_at = timezone('utc', now()),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_cheque_id;
end;
$$;

create or replace function public._insert_cheque_allocations(
  p_payment_id uuid,
  p_company_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_allocations jsonb,
  p_emp uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  alloc jsonb;
  alloc_order uuid;
  alloc_amount numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  order_row public.orders%rowtype;
  already_paid numeric(14, 2);
  remaining numeric(14, 2);
begin
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
      and company_id = p_company_id
      and customer_id = p_customer_id
      and deleted_at is null
      and status in ('placed', 'partially_delivered', 'completed');

    if not found then
      raise exception
        'Allocation order must be a placed, partially delivered, or completed order for this customer.';
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

    insert into public.payment_allocations (
      company_id,
      payment_id,
      order_id,
      amount,
      created_by,
      updated_by
    )
    values (
      p_company_id,
      p_payment_id,
      alloc_order,
      alloc_amount,
      p_emp,
      p_emp
    );
  end loop;

  if alloc_total > p_amount + 0.001 then
    raise exception 'Allocations exceed cheque amount.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Public RPCs
-- ---------------------------------------------------------------------------

create or replace function public.create_cheque(
  p_customer_id uuid,
  p_amount numeric,
  p_bank_name text,
  p_cheque_number text,
  p_holder_name text,
  p_cheque_date date,
  p_collection_date date default null,
  p_photo_path text default null,
  p_notes text default null,
  p_allocations jsonb default '[]'::jsonb,
  p_visit_id uuid default null,
  p_mark_collected boolean default false
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
  cheque_id uuid;
  label text;
  mark_collected boolean := coalesce(p_mark_collected, false)
    or p_collection_date is not null;
  initial_status text := 'awaiting_collection';
  payment_id uuid;
  bal_before numeric(14, 2);
  wallet_before numeric(14, 2);
  bal_after numeric(14, 2);
  wallet_after numeric(14, 2);
  customer_row public.customers%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Cheque amount must be greater than zero.';
  end if;

  if nullif(trim(coalesce(p_bank_name, '')), '') is null then
    raise exception 'Bank name is required.';
  end if;

  if nullif(trim(coalesce(p_cheque_number, '')), '') is null then
    raise exception 'Cheque number is required.';
  end if;

  if nullif(trim(coalesce(p_holder_name, '')), '') is null then
    raise exception 'Cheque holder name is required.';
  end if;

  if p_cheque_date is null then
    raise exception 'Cheque date is required.';
  end if;

  if mark_collected and p_collection_date is null then
    raise exception 'Collection date is required when marking a cheque collected.';
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

  if p_visit_id is not null and not exists (
    select 1 from public.customer_visits cv
    where cv.id = p_visit_id
      and cv.company_id = company
      and cv.customer_id = p_customer_id
      and cv.deleted_at is null
  ) then
    raise exception 'Visit not found for this customer.';
  end if;

  select e.branch_id into branch
  from public.employees e
  where e.id = emp and e.company_id = company and e.deleted_at is null;

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
    raise exception 'No branch available for this cheque.';
  end if;

  label := public.next_cheque_number(company);

  if mark_collected then
    initial_status := 'collected';
  end if;

  insert into public.cheques (
    company_id,
    branch_id,
    customer_id,
    employee_id,
    cheque_number_label,
    amount,
    bank_name,
    cheque_number,
    holder_name,
    cheque_date,
    collection_date,
    photo_path,
    notes,
    status,
    visit_id,
    collected_at,
    collected_by,
    created_by,
    updated_by
  )
  values (
    company,
    branch,
    p_customer_id,
    emp,
    label,
    p_amount,
    trim(p_bank_name),
    trim(p_cheque_number),
    trim(p_holder_name),
    p_cheque_date,
    case when mark_collected then p_collection_date else null end,
    nullif(trim(coalesce(p_photo_path, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    initial_status,
    p_visit_id,
    case when mark_collected then timezone('utc', now()) else null end,
    case when mark_collected then emp else null end,
    emp,
    emp
  )
  returning id into cheque_id;

  perform public._log_cheque_status(
    cheque_id, company, null, initial_status, emp, 'created'
  );

  if mark_collected then
    bal_before := customer_row.current_balance;
    wallet_before := customer_row.wallet_balance;

    payment_id := null;
    insert into public.payments (
      company_id, branch_id, customer_id, employee_id, payment_number,
      amount, method, status, reference, notes, visit_id, received_at,
      created_by, updated_by
    )
    values (
      company, branch, p_customer_id, emp, public.next_payment_number(company),
      p_amount, 'cheque', 'completed',
      'Cheque ' || trim(p_cheque_number),
      nullif(trim(coalesce(p_notes, '')), ''),
      p_visit_id,
      timezone('utc', now()),
      emp, emp
    )
    returning id into payment_id;

    perform public._insert_cheque_allocations(
      payment_id, company, p_customer_id, p_amount, p_allocations, emp
    );

    perform public.apply_payment_financials(payment_id);

    select current_balance, wallet_balance
      into bal_after, wallet_after
    from public.customers
    where id = p_customer_id;

    update public.cheques
    set
      payment_id = payment_id,
      applied_ar_amount = greatest(bal_before - bal_after, 0),
      applied_wallet_amount = greatest(wallet_after - wallet_before, 0),
      balance_applied_at = timezone('utc', now()),
      updated_by = emp
    where id = cheque_id;
  end if;

  return cheque_id;
end;
$$;

revoke all on function public.create_cheque(
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean
) from public;
grant execute on function public.create_cheque(
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean
) to authenticated;

create or replace function public.collect_cheque(
  p_cheque_id uuid,
  p_collection_date date,
  p_allocations jsonb default '[]'::jsonb,
  p_photo_path text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
  payment_id uuid;
  bal_before numeric(14, 2);
  wallet_before numeric(14, 2);
  bal_after numeric(14, 2);
  wallet_after numeric(14, 2);
  customer_row public.customers%rowtype;
  from_status text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_collection_date is null then
    raise exception 'Collection date is required.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  -- Idempotent: already collected with ledger
  if ch.status <> 'awaiting_collection'
     and ch.balance_applied_at is not null then
    return ch.id;
  end if;

  if ch.status <> 'awaiting_collection' then
    raise exception 'Only awaiting-collection cheques can be collected.';
  end if;

  from_status := ch.status;

  select * into customer_row
  from public.customers
  where id = ch.customer_id
    and company_id = company
    and deleted_at is null
  for update;

  bal_before := customer_row.current_balance;
  wallet_before := customer_row.wallet_balance;

  insert into public.payments (
    company_id, branch_id, customer_id, employee_id, payment_number,
    amount, method, status, reference, notes, visit_id, received_at,
    created_by, updated_by
  )
  values (
    company, ch.branch_id, ch.customer_id, emp, public.next_payment_number(company),
    ch.amount, 'cheque', 'completed',
    'Cheque ' || ch.cheque_number,
    coalesce(nullif(trim(coalesce(p_notes, '')), ''), ch.notes),
    ch.visit_id,
    timezone('utc', now()),
    emp, emp
  )
  returning id into payment_id;

  perform public._insert_cheque_allocations(
    payment_id, company, ch.customer_id, ch.amount, p_allocations, emp
  );

  perform public.apply_payment_financials(payment_id);

  select current_balance, wallet_balance
    into bal_after, wallet_after
  from public.customers
  where id = ch.customer_id;

  update public.cheques
  set
    status = 'collected',
    collection_date = p_collection_date,
    photo_path = coalesce(nullif(trim(coalesce(p_photo_path, '')), ''), photo_path),
    notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), notes),
    payment_id = payment_id,
    applied_ar_amount = greatest(bal_before - bal_after, 0),
    applied_wallet_amount = greatest(wallet_after - wallet_before, 0),
    balance_applied_at = timezone('utc', now()),
    collected_at = timezone('utc', now()),
    collected_by = emp,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id, company, from_status, 'collected', emp, null
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.collect_cheque(uuid, date, jsonb, text, text) from public;
grant execute on function public.collect_cheque(uuid, date, jsonb, text, text) to authenticated;

create or replace function public.deposit_cheque(p_cheque_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can deposit cheques.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'deposited' then
    return ch.id;
  end if;

  if ch.status <> 'collected' then
    raise exception 'Only collected cheques can be deposited.';
  end if;

  update public.cheques
  set
    status = 'deposited',
    deposited_at = timezone('utc', now()),
    deposited_by = emp,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id, company, 'collected', 'deposited', emp, null
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.deposit_cheque(uuid) from public;
grant execute on function public.deposit_cheque(uuid) to authenticated;

create or replace function public.clear_cheque(p_cheque_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can clear cheques.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'cleared' then
    return ch.id;
  end if;

  if ch.status <> 'deposited' then
    raise exception 'Only deposited cheques can be cleared.';
  end if;

  update public.cheques
  set
    status = 'cleared',
    cleared_at = timezone('utc', now()),
    cleared_by = emp,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id, company, 'deposited', 'cleared', emp, null
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.clear_cheque(uuid) from public;
grant execute on function public.clear_cheque(uuid) to authenticated;

create or replace function public.bounce_cheque(
  p_cheque_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
  from_status text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can bounce cheques.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'bounced' then
    -- Ensure reverse ran once
    perform public._reverse_cheque_collection_ledger(p_cheque_id);
    return ch.id;
  end if;

  if ch.status not in ('collected', 'deposited', 'cleared') then
    raise exception 'Only collected, deposited, or cleared cheques can bounce.';
  end if;

  from_status := ch.status;

  perform public._reverse_cheque_collection_ledger(p_cheque_id);

  update public.cheques
  set
    status = 'bounced',
    bounced_at = timezone('utc', now()),
    bounced_by = emp,
    bounce_reason = nullif(trim(coalesce(p_reason, '')), ''),
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id, company, from_status, 'bounced', emp, p_reason
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.bounce_cheque(uuid, text) from public;
grant execute on function public.bounce_cheque(uuid, text) to authenticated;

create or replace function public.cancel_cheque(
  p_cheque_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
  from_status text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'cancelled' then
    perform public._reverse_cheque_collection_ledger(p_cheque_id);
    return ch.id;
  end if;

  if ch.status = 'bounced' then
    raise exception 'Bounced cheques cannot be cancelled.';
  end if;

  -- Sales may cancel awaiting-collection only. Balance-affecting cancel needs Hub.
  if ch.status = 'awaiting_collection' then
    null;
  elsif ch.balance_applied_at is not null
     or ch.status in ('collected', 'deposited', 'cleared') then
    if not public.can_manage_cheque_clearance() then
      raise exception
        'Only Owner or Manager can cancel a cheque that affected balances.';
    end if;
  end if;

  from_status := ch.status;

  perform public._reverse_cheque_collection_ledger(p_cheque_id);

  update public.cheques
  set
    status = 'cancelled',
    cancelled_at = timezone('utc', now()),
    cancelled_by = emp,
    cancel_reason = nullif(trim(coalesce(p_reason, '')), ''),
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id, company, from_status, 'cancelled', emp, p_reason
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.cancel_cheque(uuid, text) from public;
grant execute on function public.cancel_cheque(uuid, text) to authenticated;

create or replace function public.cheque_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  company uuid := public.current_company_id();
  today date := (timezone('utc', now()))::date;
begin
  if company is null then
    raise exception 'Session context missing.';
  end if;

  return (
    select jsonb_build_object(
      'awaiting_collection', count(*) filter (where status = 'awaiting_collection'),
      'due_today', count(*) filter (
        where status = 'awaiting_collection'
          and (
            collection_date = today
            or (collection_date is null and cheque_date <= today)
          )
      ),
      'collected', count(*) filter (where status = 'collected'),
      'deposited', count(*) filter (where status = 'deposited'),
      'cleared', count(*) filter (where status = 'cleared'),
      'bounced', count(*) filter (where status = 'bounced'),
      'cancelled', count(*) filter (where status = 'cancelled'),
      'collected_pending_clearance_amount', coalesce(sum(amount) filter (
        where status in ('collected', 'deposited')
      ), 0)
    )
    from public.cheques
    where company_id = company
      and deleted_at is null
  );
end;
$$;

revoke all on function public.cheque_dashboard_stats() from public;
grant execute on function public.cheque_dashboard_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: private cheque-images bucket (tenant folder = company_id)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'cheque-images',
  'cheque-images',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "cheque_images_storage_select_own_company"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'cheque-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

create policy "cheque_images_storage_insert_own_company"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'cheque-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

create policy "cheque_images_storage_update_own_company"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'cheque-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  )
  with check (
    bucket_id = 'cheque-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

create policy "cheque_images_storage_delete_own_company"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'cheque-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );
