-- Separate order placement from payment settlement and fulfillment.
-- place = demand only; payment via receive_payment; stock via fulfill/complete.

-- ---------------------------------------------------------------------------
-- place_sales_order: draft → placed. No inventory. No payment settlement.
-- ---------------------------------------------------------------------------

create or replace function public.place_sales_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  item public.order_items%rowtype;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into o
  from public.orders
  where id = p_order_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if o.company_id is distinct from company then
    raise exception 'Forbidden.';
  end if;

  if o.status = 'placed' then
    return;
  end if;

  if o.status <> 'draft' then
    raise exception 'Only draft orders can be placed.';
  end if;

  if not exists (
    select 1 from public.order_items oi where oi.order_id = o.id
  ) then
    raise exception 'Add at least one product before placing the order.';
  end if;

  if o.total is null or o.total <= 0 then
    raise exception 'Order total must be greater than zero.';
  end if;

  -- Stock policy for recording demand (allow_orders_above_available_stock).
  for item in
    select * from public.order_items where order_id = o.id
  loop
    perform public.assert_order_line_stock_available(
      company,
      o.branch_id,
      item.product_id,
      item.quantity
    );
  end loop;

  -- Preserve payment_method / payment_status as intent only.
  -- Do not create payments, change customer balances, or move inventory.
  update public.orders
  set
    status = 'placed',
    submitted_at = coalesce(submitted_at, timezone('utc', now())),
    payment_status = coalesce(payment_status, 'unpaid'),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_order_id;
end;
$$;

comment on function public.place_sales_order(uuid) is
  'Marks a draft order as placed (customer demand). Does not settle payment or deduct inventory.';

revoke all on function public.place_sales_order(uuid) from public;
grant execute on function public.place_sales_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- complete_sales_order: fulfillment finish only (no payment settlement)
-- draft → place (no settle) then deliver all remaining → completed
-- placed | partially_delivered → deliver all remaining → completed
-- ---------------------------------------------------------------------------

create or replace function public.complete_sales_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  item public.order_items%rowtype;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  remaining numeric(14, 3);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into o
  from public.orders
  where id = p_order_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if o.company_id is distinct from company then
    raise exception 'Forbidden.';
  end if;

  if o.status = 'completed' then
    return;
  end if;

  if o.status = 'cancelled' then
    raise exception 'Cancelled orders cannot be completed.';
  end if;

  if o.status not in ('draft', 'placed', 'partially_delivered') then
    raise exception 'Order cannot be completed from status %.', o.status;
  end if;

  if not exists (
    select 1 from public.order_items oi where oi.order_id = o.id
  ) then
    raise exception 'Add at least one product before completing the order.';
  end if;

  if o.total is null or o.total <= 0 then
    raise exception 'Order total must be greater than zero.';
  end if;

  if o.status = 'draft' then
    -- Place without payment settlement, then fulfill below.
    update public.orders
    set
      status = 'placed',
      submitted_at = coalesce(submitted_at, timezone('utc', now())),
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = p_order_id;

    select * into o
    from public.orders
    where id = p_order_id
    for update;
  end if;

  for item in
    select * from public.order_items where order_id = o.id for update
  loop
    remaining := item.quantity - item.delivered_quantity - item.cancelled_quantity;
    if remaining <= 0 then
      continue;
    end if;

    perform public.assert_order_line_stock_available(
      company,
      o.branch_id,
      item.product_id,
      remaining
    );

    perform public.adjust_inventory(
      o.branch_id,
      item.product_id,
      -remaining,
      'sale',
      'Sold',
      null,
      'order',
      o.id
    );

    update public.order_items
    set
      delivered_quantity = delivered_quantity + remaining,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = item.id;
  end loop;

  update public.orders
  set
    status = 'completed',
    completed_at = timezone('utc', now()),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;
end;
$$;

comment on function public.complete_sales_order(uuid) is
  'Fulfills all remaining quantity and marks the order completed. Does not settle payment.';

revoke all on function public.complete_sales_order(uuid) from public;
grant execute on function public.complete_sales_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Payments may allocate to open placed/partial orders (pay before delivery)
-- as well as completed unpaid/partial orders.
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
      and status in ('placed', 'partially_delivered', 'completed');

    if not found then
      raise exception
        'Allocation order must be a placed, partially delivered, or completed order for this customer.';
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

  for alloc_row in
    select *
    from public.payment_allocations
    where payment_id = p_payment_id
  loop
    perform public.refresh_order_payment_status(alloc_row.order_id);
  end loop;
end;
$$;

revoke all on function public.apply_payment_financials(uuid) from public;
grant execute on function public.apply_payment_financials(uuid) to authenticated;

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
