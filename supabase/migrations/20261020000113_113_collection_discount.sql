-- =============================================================================
-- 113 — Collection discount + Sales Rep permission
--
-- Owners/Managers may reduce outstanding when recording a collection (cash /
-- card / bank / wallet). Sales Reps need company_settings.sales_reps_can_
-- discount_collections (default off). Discount is not cash — it settles AR
-- alongside the money received. Cheque collections stay money-only for now.
-- =============================================================================

alter table public.payments
  add column if not exists discount_amount numeric(14, 2) not null default 0;

alter table public.payments
  drop constraint if exists payments_discount_amount_non_negative;

alter table public.payments
  add constraint payments_discount_amount_non_negative
  check (discount_amount >= 0);

comment on column public.payments.discount_amount is
  'Write-off applied with this collection. Settles AR with amount; not cash.';

alter table public.company_settings
  add column if not exists sales_reps_can_discount_collections
    boolean not null default false;

comment on column public.company_settings.sales_reps_can_discount_collections is
  'When true, Sales Representatives may enter a discount on collections. Owner/Manager always may.';

-- ---------------------------------------------------------------------------
-- Permission: Owner/Manager/other Hub roles always; Sales Rep when enabled
-- ---------------------------------------------------------------------------

create or replace function public.can_discount_collections()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_role_code(), '') <> 'sales_representative'
    or coalesce(
      (
        select cs.sales_reps_can_discount_collections
        from public.company_settings cs
        where cs.company_id = public.current_company_id()
      ),
      false
    );
$$;

comment on function public.can_discount_collections() is
  'False only for Sales Representatives when the company has turned off collection discounts.';

revoke all on function public.can_discount_collections() from public;
grant execute on function public.can_discount_collections() to authenticated;

-- ---------------------------------------------------------------------------
-- receive_payment — optional discount settles with the cash amount
-- ---------------------------------------------------------------------------

drop function if exists public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid
);

create or replace function public.receive_payment(
  p_customer_id uuid,
  p_amount numeric,
  p_method text,
  p_allocations jsonb default '[]'::jsonb,
  p_reference text default null,
  p_notes text default null,
  p_visit_id uuid default null,
  p_discount_amount numeric default 0
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
  alloc_adj uuid;
  alloc_amount numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  customer_row public.customers%rowtype;
  remaining numeric(14, 2);
  approval_required boolean := false;
  payment_status text := 'completed';
  discount_amount numeric(14, 2) := coalesce(p_discount_amount, 0);
  settlement numeric(14, 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  if discount_amount < 0 then
    raise exception 'Discount cannot be negative.';
  end if;

  if discount_amount > 0.001 and not public.can_discount_collections() then
    raise exception 'Sales representatives cannot add a discount on collections for this company.';
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

  settlement := p_amount + discount_amount;

  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_order := nullif(trim(coalesce(alloc->>'order_id', '')), '')::uuid;
    alloc_adj := nullif(trim(coalesce(alloc->>'receivable_adjustment_id', '')), '')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    if alloc_amount is null or alloc_amount <= 0 then
      raise exception 'Allocation amount must be positive.';
    end if;

    remaining := public._receivable_allocation_remaining(
      company,
      p_customer_id,
      alloc_order,
      alloc_adj,
      null
    );
    if alloc_amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on this receivable.';
    end if;

    alloc_total := alloc_total + alloc_amount;
  end loop;

  if alloc_total > settlement + 0.001 then
    raise exception 'Allocations exceed payment amount plus discount.';
  end if;

  if discount_amount > 0.001
     and settlement > customer_row.current_balance + 0.001 then
    raise exception
      'Payment and discount together are more than the customer outstanding balance.';
  end if;

  payment_no := public.next_payment_number(company);

  insert into public.payments (
    company_id,
    branch_id,
    customer_id,
    employee_id,
    payment_number,
    amount,
    discount_amount,
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
    discount_amount,
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
    alloc_order := nullif(trim(coalesce(alloc->>'order_id', '')), '')::uuid;
    alloc_adj := nullif(trim(coalesce(alloc->>'receivable_adjustment_id', '')), '')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    insert into public.payment_allocations (
      company_id,
      payment_id,
      order_id,
      receivable_adjustment_id,
      amount,
      created_by,
      updated_by
    )
    values (
      company,
      payment_id,
      alloc_order,
      alloc_adj,
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

revoke all on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric
) from public;
grant execute on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric
) to authenticated;

comment on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric
) is
  'Records a collection. Optional discount_amount settles AR with the cash amount.';

-- ---------------------------------------------------------------------------
-- apply_payment_financials — AR reduced by amount + discount
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
  remaining numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  settlement numeric(14, 2);
  ar_reduction numeric(14, 2);
  overpay numeric(14, 2);
  bal_before numeric(14, 2);
  wallet_before numeric(14, 2);
  bal_after numeric(14, 2);
  wallet_after numeric(14, 2);
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
    remaining := public._receivable_allocation_remaining(
      company,
      payment_row.customer_id,
      alloc_row.order_id,
      alloc_row.receivable_adjustment_id,
      p_payment_id
    );
    if alloc_row.amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on this receivable.';
    end if;
    alloc_total := alloc_total + alloc_row.amount;
  end loop;

  settlement := payment_row.amount + coalesce(payment_row.discount_amount, 0);
  ar_reduction := least(settlement, customer_row.current_balance);
  -- Wallet credit is only cash beyond what clears outstanding (discount is not cash).
  overpay := greatest(payment_row.amount - ar_reduction, 0);
  bal_before := customer_row.current_balance;
  wallet_before := customer_row.wallet_balance;

  if payment_row.method = 'wallet' then
    -- Wallet debit is cash only; allocations already include any discount.
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

  select current_balance, wallet_balance
    into bal_after, wallet_after
  from public.customers
  where id = payment_row.customer_id;

  update public.payments
  set
    applied_ar_amount = greatest(bal_before - coalesce(bal_after, bal_before), 0),
    applied_wallet_amount =
      greatest(coalesce(wallet_after, wallet_before) - wallet_before, 0),
    applied_wallet_debit =
      greatest(wallet_before - coalesce(wallet_after, wallet_before), 0),
    updated_by = emp
  where id = p_payment_id;

  for alloc_row in
    select *
    from public.payment_allocations
    where payment_id = p_payment_id
  loop
    if alloc_row.order_id is not null then
      perform public.refresh_order_payment_status(alloc_row.order_id);
    end if;
  end loop;
end;
$$;

revoke all on function public.apply_payment_financials(uuid) from public;
grant execute on function public.apply_payment_financials(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Allocation guard — required cover is money + discount
-- ---------------------------------------------------------------------------

create or replace function public.validate_completed_payment_allocations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allocated numeric(14, 2) := 0;
  v_available numeric(14, 2) := 0;
  v_required numeric(14, 2) := 0;
  v_settlement numeric(14, 2);
begin
  if new.deleted_at is not null or new.status <> 'completed' then
    return new;
  end if;

  select coalesce(sum(pa.amount), 0)
    into v_allocated
  from public.payment_allocations pa
  where pa.payment_id = new.id;

  select coalesce(sum(greatest(o.total - coalesce(paid.amount, 0), 0)), 0)
    into v_available
  from public.orders o
  left join lateral (
    select coalesce(sum(pa.amount), 0) as amount
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = o.id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.id <> new.id
  ) paid on true
  where o.company_id = new.company_id
    and o.customer_id = new.customer_id
    and o.deleted_at is null
    and o.status in ('placed', 'partially_delivered', 'completed');

  select v_available + coalesce(
    sum(greatest(a.amount - coalesce(paid.amount, 0), 0)),
    0
  )
    into v_available
  from public.customer_receivable_adjustments a
  left join lateral (
    select coalesce(sum(pa.amount), 0) as amount
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.receivable_adjustment_id = a.id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.id <> new.id
  ) paid on true
  where a.company_id = new.company_id
    and a.customer_id = new.customer_id
    and a.kind = 'opening_balance'
    and a.reversed_at is null;

  v_settlement := new.amount + coalesce(new.discount_amount, 0);
  v_required := least(v_settlement, v_available);
  if v_required > 0.001 and v_allocated + 0.001 < v_required then
    raise exception
      'Allocate this payment across the customer''s listed orders/opening balance before saving. Only an amount above all outstanding becomes Wallet credit.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_payments_require_receivable_allocations
  on public.payments;

create constraint trigger trg_payments_require_receivable_allocations
after insert or update of status, amount, discount_amount, customer_id, deleted_at
on public.payments
deferrable initially deferred
for each row
execute function public.validate_completed_payment_allocations();

comment on function public.validate_completed_payment_allocations() is
  'Completed payments must allocate min(amount + discount, listed receivables); only cash above all outstanding becomes Wallet credit.';
