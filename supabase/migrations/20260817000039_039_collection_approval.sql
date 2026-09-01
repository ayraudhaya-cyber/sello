-- =============================================================================
-- 039 — Collection approval (tenant-configurable)
--
-- When company_settings.collection_approval_required is false (default):
--   receive_payment behaves as today — status completed, balances applied.
-- When true and the actor is a field role (not owner/admin/manager):
--   payment is stored as pending; balances / order payment_status update only
--   after approve_collection. reject_collection keeps the row for audit.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Company setting (default preserves current behaviour)
-- ---------------------------------------------------------------------------

alter table public.company_settings
  add column if not exists collection_approval_required
    boolean not null default false;

comment on column public.company_settings.collection_approval_required is
  'When true, Sales Rep collections stay Pending Review until Owner/Manager approve.';

-- ---------------------------------------------------------------------------
-- Payment review audit + rejected status
-- ---------------------------------------------------------------------------

alter table public.payments
  drop constraint if exists payments_status_allowed;

alter table public.payments
  add constraint payments_status_allowed check (
    status in ('completed', 'pending', 'refunded', 'cancelled', 'rejected')
  );

alter table public.payments
  add column if not exists reviewed_by uuid
    references public.employees (id) on delete set null;

alter table public.payments
  add column if not exists reviewed_at timestamptz;

alter table public.payments
  add column if not exists rejection_reason text;

alter table public.payments
  drop constraint if exists payments_rejection_reason_not_blank;

alter table public.payments
  add constraint payments_rejection_reason_not_blank
    check (rejection_reason is null or length(trim(rejection_reason)) > 0);

create index if not exists payments_company_pending_review_idx
  on public.payments (company_id, received_at desc)
  where deleted_at is null and status = 'pending';

-- ---------------------------------------------------------------------------
-- Role helpers — Hub approvers vs field collectors
-- ---------------------------------------------------------------------------

create or replace function public.can_auto_apply_collections()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role_code(), '') in (
    'owner',
    'administrator',
    'manager'
  );
$$;

comment on function public.can_auto_apply_collections() is
  'Owner / Administrator / Manager collections apply immediately even when approval is required.';

create or replace function public.can_review_collections()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_auto_apply_collections();
$$;

revoke all on function public.can_auto_apply_collections() from public;
grant execute on function public.can_auto_apply_collections() to authenticated;
revoke all on function public.can_review_collections() from public;
grant execute on function public.can_review_collections() to authenticated;

-- ---------------------------------------------------------------------------
-- Apply financial effects for a completed payment (balances + order status)
-- Idempotent only when called once while transitioning pending → completed.
-- ---------------------------------------------------------------------------

create or replace function public.apply_payment_financials(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  payment_row public.payments%rowtype;
  customer_row public.customers%rowtype;
  alloc_row public.payment_allocations%rowtype;
  order_row public.orders%rowtype;
  already_paid numeric(14, 2);
  remaining numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  ar_reduction numeric(14, 2);
  overpay numeric(14, 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into payment_row
  from public.payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  select * into customer_row
  from public.customers
  where id = payment_row.customer_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Customer not found.';
  end if;

  if payment_row.method = 'wallet'
     and customer_row.wallet_balance < payment_row.amount then
    raise exception 'Insufficient wallet balance.';
  end if;

  for alloc_row in
    select *
    from public.payment_allocations
    where payment_id = p_payment_id
  loop
    select * into order_row
    from public.orders
    where id = alloc_row.order_id
      and company_id = company
      and customer_id = payment_row.customer_id
      and deleted_at is null
      and status = 'completed';

    if not found then
      raise exception 'Allocation order is not a completed order for this customer.';
    end if;

    select coalesce(sum(pa.amount), 0)
      into already_paid
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = alloc_row.order_id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.id <> p_payment_id;

    remaining := order_row.total - already_paid;
    if alloc_row.amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on order %', order_row.order_number;
    end if;

    alloc_total := alloc_total + alloc_row.amount;
  end loop;

  if alloc_total > payment_row.amount + 0.001 then
    raise exception 'Allocations exceed payment amount.';
  end if;

  for alloc_row in
    select *
    from public.payment_allocations
    where payment_id = p_payment_id
  loop
    perform public.refresh_order_payment_status(alloc_row.order_id);
  end loop;

  ar_reduction := least(payment_row.amount, customer_row.current_balance);
  overpay := greatest(payment_row.amount - alloc_total, 0);

  if payment_row.method = 'wallet' then
    update public.customers
    set
      wallet_balance = wallet_balance - payment_row.amount,
      current_balance = greatest(current_balance - alloc_total, 0),
      updated_by = emp
    where id = payment_row.customer_id;
  else
    update public.customers
    set
      current_balance = greatest(current_balance - ar_reduction, 0),
      wallet_balance = wallet_balance + overpay,
      updated_by = emp
    where id = payment_row.customer_id;
  end if;
end;
$$;

revoke all on function public.apply_payment_financials(uuid) from public;
grant execute on function public.apply_payment_financials(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- receive_payment — pending when approval required for field roles
-- ---------------------------------------------------------------------------

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

  -- Validate wallet at submit even for pending (fail early).
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

revoke all on function public.receive_payment(uuid, numeric, text, jsonb, text, text, uuid) from public;
grant execute on function public.receive_payment(uuid, numeric, text, jsonb, text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Approve pending collection — apply balances exactly once
-- ---------------------------------------------------------------------------

create or replace function public.approve_collection(p_payment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  payment_row public.payments%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_review_collections() then
    raise exception 'Not permitted to approve collections.';
  end if;

  select * into payment_row
  from public.payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if payment_row.status <> 'pending' then
    raise exception 'Only pending collections can be approved.';
  end if;

  -- Mark completed first so apply_payment_financials counts this row correctly
  -- when refreshing order payment status (completed allocations only).
  update public.payments
  set
    status = 'completed',
    reviewed_by = emp,
    reviewed_at = timezone('utc', now()),
    rejection_reason = null,
    updated_by = emp
  where id = p_payment_id;

  perform public.apply_payment_financials(p_payment_id);

  return p_payment_id;
end;
$$;

revoke all on function public.approve_collection(uuid) from public;
grant execute on function public.approve_collection(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reject pending collection — no balance change; keep audit row
-- ---------------------------------------------------------------------------

create or replace function public.reject_collection(
  p_payment_id uuid,
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
  payment_row public.payments%rowtype;
  reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_review_collections() then
    raise exception 'Not permitted to reject collections.';
  end if;

  select * into payment_row
  from public.payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if payment_row.status <> 'pending' then
    raise exception 'Only pending collections can be rejected.';
  end if;

  update public.payments
  set
    status = 'rejected',
    reviewed_by = emp,
    reviewed_at = timezone('utc', now()),
    rejection_reason = reason,
    cancelled_at = timezone('utc', now()),
    updated_by = emp
  where id = p_payment_id;

  return p_payment_id;
end;
$$;

revoke all on function public.reject_collection(uuid, text) from public;
grant execute on function public.reject_collection(uuid, text) to authenticated;

comment on function public.approve_collection(uuid) is
  'Owner/Manager approval: apply customer balances and order payment status once.';

comment on function public.reject_collection(uuid, text) is
  'Owner/Manager rejection: keep the collection for audit without updating balances.';
