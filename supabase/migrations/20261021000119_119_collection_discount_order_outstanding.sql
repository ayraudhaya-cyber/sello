-- =============================================================================
-- 119 — Collection discount may cover order outstanding, not only AR balance
--
-- 113 blocked amount + discount when it exceeded customers.current_balance
-- (delivered unpaid AR). Order outstanding can be higher (e.g. placed not yet
-- delivered), so a full order collection with discount failed even when the
-- allocation fit the order remaining. Cash-only collections already allow that
-- path; discount collections should too. Cap write-off by allocation remaining
-- instead, and require the settlement to be fully allocated when discounted.
-- =============================================================================

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

  -- Discount must be applied to listed receivables (order / opening balance).
  -- Do not compare settlement to customers.current_balance — that is delivered
  -- AR only and can be lower than order outstanding.
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

comment on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric
) is
  'Records a collection. Optional discount settles with cash against allocated receivables; not capped by delivered-only customer AR.';
