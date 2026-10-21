-- =============================================================================
-- 120 — Allow discount-only collections (zero cash)
--
-- A collection may write off outstanding with discount alone (amount = 0).
-- Previously payments.amount > 0 blocked that after the UI trimmed wallet/cash
-- to leave room for a full discount.
-- =============================================================================

alter table public.payments
  drop constraint if exists payments_amount_positive;

alter table public.payments
  drop constraint if exists payments_amount_non_negative;

alter table public.payments
  add constraint payments_amount_non_negative
  check (amount >= 0);

alter table public.payments
  drop constraint if exists payments_settlement_positive;

alter table public.payments
  add constraint payments_settlement_positive
  check (amount + coalesce(discount_amount, 0) > 0);

comment on constraint payments_amount_non_negative on public.payments is
  'Cash may be zero when discount_amount alone settles the collection.';

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
  cash_amount numeric(14, 2) := coalesce(p_amount, 0);
  method_code text := p_method;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if cash_amount < 0 then
    raise exception 'Payment amount cannot be negative.';
  end if;

  if discount_amount < 0 then
    raise exception 'Discount cannot be negative.';
  end if;

  if cash_amount <= 0.001 and discount_amount <= 0.001 then
    raise exception 'Enter a payment amount or a discount greater than zero.';
  end if;

  if discount_amount > 0.001 and not public.can_discount_collections() then
    raise exception 'Sales representatives cannot add a discount on collections for this company.';
  end if;

  if method_code not in ('cash', 'card', 'bank_transfer', 'wallet', 'credit_settlement') then
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

  if method_code = 'wallet' and cash_amount > 0.001
     and customer_row.wallet_balance < cash_amount then
    raise exception 'Insufficient wallet balance.';
  end if;

  -- Discount-only write-offs are recorded as cash method (no wallet debit).
  if cash_amount <= 0.001 and method_code = 'wallet' then
    method_code := 'cash';
  end if;

  settlement := cash_amount + discount_amount;

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

  if discount_amount > 0.001 and alloc_total + 0.001 < settlement then
    raise exception
      'Allocate the full payment and discount to the order or opening balance.';
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
    cash_amount,
    discount_amount,
    method_code,
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

comment on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric
) is
  'Records a collection. Cash may be zero when discount alone settles allocated receivables.';
