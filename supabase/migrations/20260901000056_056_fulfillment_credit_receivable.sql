-- Recognize customer AR only for value actually fulfilled, not for placed demand.
-- Payments remain a separate event (receive_payment). No historical backfill.

-- ---------------------------------------------------------------------------
-- Track gross delivered value already posted through AR recognition.
-- Default 0: historical completed orders keep existing current_balance as-is.
-- ---------------------------------------------------------------------------

alter table public.orders
  add column if not exists recognized_receivable_value numeric(14, 2) not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_recognized_receivable_non_negative'
  ) then
    alter table public.orders
      add constraint orders_recognized_receivable_non_negative
        check (recognized_receivable_value >= 0);
  end if;
end $$;

comment on column public.orders.recognized_receivable_value is
  'Gross delivered financial value already posted toward customer AR (before payment netting). Not rewritten for historical completed orders.';

comment on column public.customers.current_balance is
  'Outstanding receivable: delivered unpaid credit value. Increased on fulfillment; reduced by receive_payment. Placed demand does not add AR.';

-- ---------------------------------------------------------------------------
-- Delivered financial value = order.total allocated by delivered / ordered lines.
-- Header discount and tax follow the same ratio. Cancelled quantity is excluded.
-- ---------------------------------------------------------------------------

create or replace function public.order_delivered_financial_value(p_order_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  o_subtotal numeric(14, 2);
  o_total numeric(14, 2);
  delivered_lines numeric(14, 6);
begin
  select subtotal, total
    into o_subtotal, o_total
  from public.orders
  where id = p_order_id
    and deleted_at is null;

  if o_subtotal is null or o_total is null or o_subtotal <= 0 or o_total <= 0 then
    return 0;
  end if;

  select coalesce(sum(
    oi.line_total * oi.delivered_quantity / nullif(oi.quantity, 0)
  ), 0)
    into delivered_lines
  from public.order_items oi
  where oi.order_id = p_order_id;

  if delivered_lines <= 0 then
    return 0;
  end if;

  return round((o_total * delivered_lines / o_subtotal)::numeric, 2);
end;
$$;

comment on function public.order_delivered_financial_value(uuid) is
  'Order total allocated to delivered quantity. Used for incremental credit AR recognition.';

revoke all on function public.order_delivered_financial_value(uuid) from public;

-- ---------------------------------------------------------------------------
-- Post incremental unpaid delivered value to customers.current_balance.
-- Nets completed payment allocations so prepayment does not inflate AR.
-- ---------------------------------------------------------------------------

create or replace function public.apply_order_fulfillment_receivable(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  delivered_after numeric(14, 2);
  paid numeric(14, 2);
  stored numeric(14, 2);
  delta numeric(14, 2);
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

  delivered_after := public.order_delivered_financial_value(p_order_id);
  stored := coalesce(o.recognized_receivable_value, 0);

  select coalesce(sum(pa.amount), 0)
    into paid
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = o.id
    and p.deleted_at is null
    and p.status = 'completed';

  delta := greatest(delivered_after - paid, 0) - greatest(stored - paid, 0);

  update public.orders
  set
    recognized_receivable_value = delivered_after,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  update public.customers
  set
    current_balance = greatest(current_balance + delta, 0),
    last_purchase_at = case
      when delivered_after > stored then greatest(
        coalesce(last_purchase_at, o.ordered_at),
        coalesce(o.ordered_at, timezone('utc', now()))
      )
      else last_purchase_at
    end,
    updated_by = emp
  where id = o.customer_id
    and company_id = company
    and deleted_at is null;

  if not found then
    raise exception 'Customer not found.';
  end if;
end;
$$;

comment on function public.apply_order_fulfillment_receivable(uuid) is
  'Increments customer AR by newly delivered unpaid value. Does not create payments.';

revoke all on function public.apply_order_fulfillment_receivable(uuid) from public;

-- Placement must never create AR or fake payments.
create or replace function public.settle_sales_order_payment(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Superseded by 055/056: place does not settle; AR is recognized on fulfillment;
  -- cash/card/wallet collections use receive_payment.
  return;
end;
$$;

comment on function public.settle_sales_order_payment(uuid) is
  'No-op. Payment is recorded via receive_payment; AR is recognized on fulfillment.';

-- ---------------------------------------------------------------------------
-- fulfill_order_items: inventory + incremental AR. No payment rows.
-- ---------------------------------------------------------------------------

create or replace function public.fulfill_order_items(
  p_order_id uuid,
  p_lines jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  line_rec record;
  item public.order_items%rowtype;
  deliver_qty numeric(14, 3);
  remaining numeric(14, 3);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Provide at least one fulfillment line.';
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

  if o.status not in ('placed', 'partially_delivered') then
    raise exception 'Only placed or partially delivered orders can be fulfilled.';
  end if;

  for line_rec in
    select
      (elem->>'order_item_id')::uuid as order_item_id,
      (elem->>'quantity')::numeric as quantity
    from jsonb_array_elements(p_lines) as elem
  loop
    if line_rec.order_item_id is null then
      raise exception 'Each fulfillment line requires order_item_id.';
    end if;

    deliver_qty := coalesce(line_rec.quantity, 0);
    if deliver_qty <= 0 then
      raise exception 'Fulfillment quantity must be greater than zero.';
    end if;

    select * into item
    from public.order_items
    where id = line_rec.order_item_id
      and order_id = o.id
    for update;

    if not found then
      raise exception 'Order line not found on this order.';
    end if;

    remaining := item.quantity - item.delivered_quantity - item.cancelled_quantity;
    if deliver_qty > remaining then
      raise exception
        'Cannot deliver % for line; only % remaining.',
        deliver_qty,
        remaining;
    end if;

    perform public.assert_order_line_stock_available(
      company,
      o.branch_id,
      item.product_id,
      deliver_qty
    );

    perform public.adjust_inventory(
      o.branch_id,
      item.product_id,
      -deliver_qty,
      'sale',
      'Fulfilled',
      null,
      'order',
      o.id
    );

    update public.order_items
    set
      delivered_quantity = delivered_quantity + deliver_qty,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = item.id;
  end loop;

  perform public.apply_order_fulfillment_receivable(o.id);

  update public.orders
  set
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.refresh_order_fulfillment_status(o.id);
end;
$$;

comment on function public.fulfill_order_items(uuid, jsonb) is
  'Delivers listed quantities, deducts inventory once, and recognizes unpaid delivered AR.';

revoke all on function public.fulfill_order_items(uuid, jsonb) from public;
grant execute on function public.fulfill_order_items(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- complete_sales_order: fulfill remaining + AR. Does not create payments.
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

  perform public.apply_order_fulfillment_receivable(o.id);

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
  'Fulfills remaining quantity, recognizes unpaid delivered AR, and marks completed. Does not settle payment.';

revoke all on function public.complete_sales_order(uuid) from public;
grant execute on function public.complete_sales_order(uuid) to authenticated;
