-- =============================================================================
-- 130 — Hold stock when an order is placed. On-hand drops only at delivery.
--
-- Available for the next order is on-hand minus reserved. Physical quantity
-- is unchanged by placing, cancelling undelivered units, or this backfill.
-- Delivery consumes the hold and reduces on-hand together.
--
-- Existing placed and partially delivered orders are reserved from their
-- undelivered remainder. Where that already exceeds on-hand, available
-- becomes zero and those orders stay open.
-- =============================================================================

comment on column public.inventory.reserved_quantity is
  'Quantity held for open orders at this branch. Available = quantity - reserved_quantity. On-hand quantity changes only when goods move.';

comment on column public.company_settings.inventory_movement_policy is
  'Retained preference. Open orders reserve stock when placed, and on-hand quantity drops when delivery is recorded.';

-- ---------------------------------------------------------------------------
-- Lock one variant row, creating a zero on-hand row when the branch has none.
-- ---------------------------------------------------------------------------

create or replace function public.ensure_variant_inventory_locked(
  p_company_id uuid,
  p_branch_id uuid,
  p_variant_id uuid
)
returns public.inventory
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  v public.product_variants%rowtype;
  inv public.inventory%rowtype;
begin
  if emp is null or p_company_id is null or p_branch_id is null or p_variant_id is null then
    raise exception 'Session context missing.';
  end if;

  select * into v
  from public.product_variants
  where id = p_variant_id
    and company_id = p_company_id;

  if not found then
    select * into inv
    from public.inventory
    where company_id = p_company_id
      and branch_id = p_branch_id
      and variant_id = p_variant_id
    for update;

    if not found then
      raise exception 'Variant not found for stock check.';
    end if;

    return inv;
  end if;

  if v.deleted_at is null then
  insert into public.inventory (
    company_id,
    branch_id,
    product_id,
    variant_id,
    quantity,
    is_default_variant,
    created_by,
    updated_by
  )
  values (
    p_company_id,
    p_branch_id,
    v.product_id,
    v.id,
    0,
    v.is_default,
    emp,
    emp
  )
  on conflict (company_id, branch_id, variant_id) do nothing;
  end if;

  select * into inv
  from public.inventory
  where company_id = p_company_id
    and branch_id = p_branch_id
    and variant_id = v.id
  for update;

  if not found then
    raise exception 'Inventory row not found.';
  end if;

  return inv;
end;
$$;

revoke all on function public.ensure_variant_inventory_locked(uuid, uuid, uuid)
  from public, anon, authenticated;

-- Lock every variant in id order so two orders cannot deadlock.
create or replace function public.lock_order_variant_stock(
  p_company_id uuid,
  p_branch_id uuid,
  p_variant_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_variant_ids is null then
    return;
  end if;

  for v_id in
    select distinct variant_id
    from unnest(p_variant_ids) as t(variant_id)
    where variant_id is not null
    order by 1
  loop
    perform public.ensure_variant_inventory_locked(p_company_id, p_branch_id, v_id);
  end loop;
end;
$$;

revoke all on function public.lock_order_variant_stock(uuid, uuid, uuid[])
  from public, anon, authenticated;

-- Positive delta holds units. Negative delta releases them. Quantity is never changed.
-- Returns true when a positive hold exceeds free stock and is still applied.
create or replace function public.apply_order_stock_hold(
  p_company_id uuid,
  p_branch_id uuid,
  p_variant_id uuid,
  p_delta numeric,
  p_force boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  inv public.inventory%rowtype;
  allow_above boolean := false;
  available numeric(14, 3);
  display_name text;
  v public.product_variants%rowtype;
  short boolean := false;
begin
  if p_delta is null or p_delta = 0 or p_variant_id is null then
    return false;
  end if;

  if p_delta < 0 then
    select * into inv
    from public.inventory
    where company_id = p_company_id
      and branch_id = p_branch_id
      and variant_id = p_variant_id
    for update;

    if not found then
      return false;
    end if;

    update public.inventory
    set
      reserved_quantity = greatest(reserved_quantity + p_delta, 0),
      updated_by = public.current_employee_id()
    where id = inv.id;

    return false;
  end if;

  inv := public.ensure_variant_inventory_locked(p_company_id, p_branch_id, p_variant_id);

  select coalesce(cs.allow_orders_above_available_stock, false)
    into allow_above
  from public.company_settings cs
  where cs.company_id = p_company_id;

  available := coalesce(inv.quantity, 0) - coalesce(inv.reserved_quantity, 0);
  if available < 0 then
    available := 0;
  end if;

  short := p_delta > available;

  if short and not p_force and not allow_above then
    select * into v
    from public.product_variants
    where id = p_variant_id
      and company_id = p_company_id;

    select p.name into display_name
    from public.products p
    where p.id = v.product_id
      and p.company_id = p_company_id;

    if v.label is not null and length(trim(v.label)) > 0 then
      display_name := coalesce(display_name, 'product') || ' (' || trim(v.label) || ')';
    end if;

    raise exception
      'Not enough stock for %. Only % available.',
      coalesce(display_name, 'product'),
      available;
  end if;

  update public.inventory
  set
    reserved_quantity = reserved_quantity + p_delta,
    updated_by = public.current_employee_id()
  where id = inv.id;

  return short;
end;
$$;

revoke all on function public.apply_order_stock_hold(uuid, uuid, uuid, numeric, boolean)
  from public, anon, authenticated;

-- Delivery: older open orders keep the physical units. Then release only the
-- delivered quantity from the shared hold and reduce on-hand by that amount.
create or replace function public.consume_reserved_stock(
  p_branch_id uuid,
  p_product_id uuid,
  p_variant_id uuid,
  p_quantity numeric,
  p_order_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
  inv public.inventory%rowtype;
  current_order public.orders%rowtype;
  older_need numeric(14, 3) := 0;
  open_need numeric(14, 3) := 0;
  deliverable numeric(14, 3) := 0;
begin
  if p_quantity is null or p_quantity <= 0 then
    return;
  end if;

  if company is null or p_variant_id is null or p_order_id is null then
    raise exception 'Session context missing.';
  end if;

  select * into current_order
  from public.orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null;

  if not found then
    raise exception 'Order not found.';
  end if;

  inv := public.ensure_variant_inventory_locked(company, p_branch_id, p_variant_id);

  -- Same branch and variant only. Older means an earlier ordered_at, then a
  -- smaller order id when the timestamps match.
  select coalesce(sum(greatest(
    oi.quantity - oi.delivered_quantity - oi.cancelled_quantity,
    0
  )), 0)
    into older_need
  from public.orders o
  join public.order_items oi on oi.order_id = o.id
  where o.company_id = company
    and o.branch_id = p_branch_id
    and o.deleted_at is null
    and o.status in ('placed', 'partially_delivered')
    and oi.variant_id = p_variant_id
    and o.id <> p_order_id
    and row(
      coalesce(o.ordered_at, '-infinity'::timestamptz),
      o.id
    ) < row(
      coalesce(current_order.ordered_at, '-infinity'::timestamptz),
      current_order.id
    );

  deliverable := coalesce(inv.quantity, 0) - coalesce(older_need, 0);
  if deliverable < 0 then
    deliverable := 0;
  end if;

  if p_quantity > deliverable then
    raise exception
      'Not enough stock for this delivery. Older open orders still need %. Only % can be delivered now.',
      older_need,
      deliverable;
  end if;

  -- Rebuild the hold from what is still undelivered, minus this delivery.
  -- The line's delivered quantity is updated by the caller after this returns,
  -- so this delivery is still included in open_need.
  select coalesce(sum(greatest(
    oi.quantity - oi.delivered_quantity - oi.cancelled_quantity,
    0
  )), 0)
    into open_need
  from public.orders o
  join public.order_items oi on oi.order_id = o.id
  where o.company_id = company
    and o.branch_id = p_branch_id
    and o.deleted_at is null
    and o.status in ('placed', 'partially_delivered')
    and oi.variant_id = p_variant_id;

  update public.inventory
  set
    reserved_quantity = greatest(open_need - p_quantity, 0),
    updated_by = public.current_employee_id()
  where id = inv.id;

  perform public.adjust_inventory(
    p_branch_id,
    p_product_id,
    -p_quantity,
    'sale',
    nullif(trim(coalesce(p_reason, '')), ''),
    null,
    'order',
    p_order_id,
    p_variant_id
  );
end;
$$;

revoke all on function public.consume_reserved_stock(uuid, uuid, uuid, numeric, uuid, text)
  from public, anon, authenticated;

-- Undo delivery: put units back on hand and hold them for the open order again.
create or replace function public.restock_and_rehold(
  p_branch_id uuid,
  p_product_id uuid,
  p_variant_id uuid,
  p_quantity numeric,
  p_order_id uuid,
  p_reason text,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
begin
  if p_quantity is null or p_quantity <= 0 then
    return;
  end if;

  perform public.adjust_inventory(
    p_branch_id,
    p_product_id,
    p_quantity,
    'correction',
    nullif(trim(coalesce(p_reason, '')), ''),
    p_notes,
    'order',
    p_order_id,
    p_variant_id
  );

  perform public.apply_order_stock_hold(
    company,
    p_branch_id,
    p_variant_id,
    p_quantity,
    true
  );
end;
$$;

revoke all on function public.restock_and_rehold(uuid, uuid, uuid, numeric, uuid, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Backfill holds for orders already placed. Does not change on-hand quantity.
-- ---------------------------------------------------------------------------

do $backfill$
declare
  qty_before numeric;
  qty_after numeric;
begin
  select coalesce(sum(quantity), 0) into qty_before from public.inventory;

  -- Wait for in-flight place, delivery, and cancel work, then block new
  -- changes to those orders until this backfill commits.
  perform 1
  from public.orders
  where deleted_at is null
    and status in ('draft', 'placed', 'partially_delivered')
  for update;

  -- Absolute assignment from current open demand. A second run sets the same
  -- reserved quantities again; it does not add them on top.
  drop table if exists _order_stock_demand;

  create temporary table _order_stock_demand on commit drop as
  select
    o.company_id,
    o.branch_id,
    oi.variant_id,
    sum(greatest(
      oi.quantity
        - coalesce(oi.delivered_quantity, 0)
        - coalesce(oi.cancelled_quantity, 0),
      0
    )) as demand
  from public.orders o
  join public.order_items oi on oi.order_id = o.id
  where o.deleted_at is null
    and o.status in ('placed', 'partially_delivered')
    and oi.variant_id is not null
  group by o.company_id, o.branch_id, oi.variant_id
  having sum(greatest(
    oi.quantity
      - coalesce(oi.delivered_quantity, 0)
      - coalesce(oi.cancelled_quantity, 0),
    0
  )) > 0;

  update public.inventory i
  set reserved_quantity = d.demand
  from _order_stock_demand d
  where i.company_id = d.company_id
    and i.branch_id = d.branch_id
    and i.variant_id = d.variant_id;

  insert into public.inventory (
    company_id,
    branch_id,
    product_id,
    variant_id,
    quantity,
    reserved_quantity,
    is_default_variant
  )
  select
    d.company_id,
    d.branch_id,
    v.product_id,
    d.variant_id,
    0,
    d.demand,
    coalesce(v.is_default, false)
  from _order_stock_demand d
  join public.product_variants v on v.id = d.variant_id
  where not exists (
    select 1
    from public.inventory i
    where i.company_id = d.company_id
      and i.branch_id = d.branch_id
      and i.variant_id = d.variant_id
  );

  update public.inventory i
  set reserved_quantity = 0
  where not exists (
    select 1
    from _order_stock_demand d
    where d.company_id = i.company_id
      and d.branch_id = i.branch_id
      and d.variant_id = i.variant_id
  );

  select coalesce(sum(quantity), 0) into qty_after from public.inventory;

  if qty_before is distinct from qty_after then
    raise exception 'Stock reservation backfill changed on-hand quantity.';
  end if;
end;
$backfill$;

-- ---------------------------------------------------------------------------
-- place_sales_order — hold each line before the order is placed
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
  customer_name text;
  insufficient boolean := false;
  short boolean := false;
  variant_ids uuid[];
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

  select coalesce(array_agg(distinct oi.variant_id), '{}')
    into variant_ids
  from public.order_items oi
  where oi.order_id = o.id;

  if exists (
    select 1 from public.order_items oi
    where oi.order_id = o.id and oi.variant_id is null
  ) then
    raise exception 'Order line missing variant_id.';
  end if;

  perform public.lock_order_variant_stock(company, o.branch_id, variant_ids);

  for item in
    select * from public.order_items
    where order_id = o.id
    order by variant_id
  loop
    short := public.apply_order_stock_hold(
      company,
      o.branch_id,
      item.variant_id,
      item.quantity,
      false
    );
    if short then
      insufficient := true;
    end if;
  end loop;

  update public.orders
  set
    status = 'placed',
    submitted_at = coalesce(submitted_at, timezone('utc', now())),
    payment_status = coalesce(payment_status, 'unpaid'),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_order_id;

  select coalesce(nullif(trim(c.name), ''), 'Customer')
    into customer_name
  from public.customers c
  where c.id = o.customer_id;

  perform public.emit_notifications_for_hub_roles(
    company,
    'orders',
    'order_placed',
    'New order received',
    'Order from ' || customer_name || ' is ready for fulfillment.',
    'normal',
    emp,
    'order',
    o.id,
    '/hub/orders?id=' || o.id::text,
    '{}'::jsonb,
    null,
    'order_placed:' || o.id::text
  );

  if insufficient then
    perform public.emit_notifications_for_hub_roles(
      company,
      'orders',
      'order_insufficient_stock',
      'Order waiting for stock',
      'Order from ' || customer_name || ' cannot be fully fulfilled with current stock.',
      'high',
      emp,
      'order',
      o.id,
      '/hub/orders?id=' || o.id::text,
      '{}'::jsonb,
      null,
      'order_insufficient_stock:' || o.id::text
    );
  end if;
end;
$$;

comment on function public.place_sales_order(uuid) is
  'Marks a draft as placed and reserves each line. Does not change on-hand quantity or payments.';

-- ---------------------------------------------------------------------------
-- fulfill_order_items — consume the hold and reduce on-hand for delivered units
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
  status_before text;
  status_after text;
  customer_name text;
  remaining_units numeric(14, 3);
  variant_ids uuid[];
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_record_order_delivery() then
    raise exception 'Sales representatives cannot record delivery for this company.';
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

  status_before := o.status;

  select coalesce(array_agg(distinct oi.variant_id), '{}')
    into variant_ids
  from public.order_items oi
  where oi.order_id = o.id;

  perform public.lock_order_variant_stock(company, o.branch_id, variant_ids);

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

    if item.variant_id is null then
      raise exception 'Order line missing variant_id.';
    end if;

    remaining := item.quantity - item.delivered_quantity - item.cancelled_quantity;
    if deliver_qty > remaining then
      raise exception
        'Cannot deliver % for line; only % remaining.',
        deliver_qty,
        remaining;
    end if;

    perform public.consume_reserved_stock(
      o.branch_id,
      item.product_id,
      item.variant_id,
      deliver_qty,
      o.id,
      'Fulfilled'
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

  select status into status_after
  from public.orders
  where id = o.id;

  if status_before is distinct from 'partially_delivered'
     and status_after = 'partially_delivered' then
    select coalesce(sum(
      greatest(oi.quantity - oi.delivered_quantity - oi.cancelled_quantity, 0)
    ), 0)
      into remaining_units
    from public.order_items oi
    where oi.order_id = o.id;

    select coalesce(nullif(trim(c.name), ''), 'Customer')
      into customer_name
    from public.customers c
    where c.id = o.customer_id;

    perform public.emit_notifications_for_hub_roles(
      company,
      'orders',
      'order_partially_delivered',
      'Order partially delivered',
      'Order from ' || customer_name || ' was partially delivered. '
        || trim(to_char(remaining_units, 'FM999999990.###'))
        || ' items remain.',
      'normal',
      emp,
      'order',
      o.id,
      '/hub/orders?id=' || o.id::text,
      '{}'::jsonb,
      emp,
      'order_partially_delivered:' || o.id::text
    );
  end if;
end;
$$;

comment on function public.fulfill_order_items(uuid, jsonb) is
  'Delivers listed quantities, consumes their reservation, deducts on-hand stock, and recognizes AR. Sales Reps require sales_reps_can_record_delivery.';

-- ---------------------------------------------------------------------------
-- complete_sales_order — draft holds then delivers; open orders only consume
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
  status_before text;
  variant_ids uuid[];
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_record_order_delivery() then
    raise exception 'Sales representatives cannot record delivery for this company.';
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

  status_before := o.status;

  if exists (
    select 1 from public.order_items oi
    where oi.order_id = o.id and oi.variant_id is null
  ) then
    raise exception 'Order line missing variant_id.';
  end if;

  select coalesce(array_agg(distinct oi.variant_id), '{}')
    into variant_ids
  from public.order_items oi
  where oi.order_id = o.id;

  perform public.lock_order_variant_stock(company, o.branch_id, variant_ids);

  if status_before = 'draft' then
    for item in
      select * from public.order_items
      where order_id = o.id
      order by variant_id
    loop
      remaining := item.quantity - item.delivered_quantity - item.cancelled_quantity;
      if remaining > 0 then
        perform public.apply_order_stock_hold(
          company,
          o.branch_id,
          item.variant_id,
          remaining,
          false
        );
      end if;
    end loop;

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

    perform public.consume_reserved_stock(
      o.branch_id,
      item.product_id,
      item.variant_id,
      remaining,
      o.id,
      'Sold'
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
  'Delivers the remaining quantity, consumes the reservation, recognizes unpaid delivered AR, and marks the order completed. A draft is held and delivered in the same step. Sales Reps require sales_reps_can_record_delivery.';

-- ---------------------------------------------------------------------------
-- cancel_order_remaining — release the hold. On-hand quantity stays.
-- ---------------------------------------------------------------------------

create or replace function public.cancel_order_remaining(
  p_order_id uuid,
  p_lines jsonb default null
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
  item public.order_items%rowtype;
  line_rec record;
  cancel_qty numeric(14, 3);
  remaining numeric(14, 3);
  had_delivery boolean;
  variant_ids uuid[];
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

  if o.status not in ('placed', 'partially_delivered') then
    raise exception 'Only open placed orders can cancel remaining quantities.';
  end if;

  select exists (
    select 1
    from public.order_items oi
    where oi.order_id = o.id
      and oi.delivered_quantity > 0
  ) into had_delivery;

  select coalesce(array_agg(distinct oi.variant_id), '{}')
    into variant_ids
  from public.order_items oi
  where oi.order_id = o.id;

  perform public.lock_order_variant_stock(company, o.branch_id, variant_ids);

  if p_lines is null then
    for item in
      select * from public.order_items where order_id = o.id for update
    loop
      remaining := item.quantity - item.delivered_quantity - item.cancelled_quantity;
      if remaining > 0 then
        perform public.apply_order_stock_hold(
          company,
          o.branch_id,
          item.variant_id,
          -remaining,
          false
        );
        update public.order_items
        set
          cancelled_quantity = cancelled_quantity + remaining,
          updated_by = emp,
          updated_at = timezone('utc', now())
        where id = item.id;
      end if;
    end loop;
  else
    if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
      raise exception 'Provide cancellation lines or omit p_lines to cancel all remaining.';
    end if;

    for line_rec in
      select
        (elem->>'order_item_id')::uuid as order_item_id,
        (elem->>'quantity')::numeric as quantity
      from jsonb_array_elements(p_lines) as elem
    loop
      if line_rec.order_item_id is null then
        raise exception 'Each cancellation line requires order_item_id.';
      end if;

      cancel_qty := coalesce(line_rec.quantity, 0);
      if cancel_qty <= 0 then
        raise exception 'Cancellation quantity must be greater than zero.';
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
      if cancel_qty > remaining then
        raise exception
          'Cannot cancel % for line; only % remaining.',
          cancel_qty,
          remaining;
      end if;

      perform public.apply_order_stock_hold(
        company,
        o.branch_id,
        item.variant_id,
        -cancel_qty,
        false
      );

      update public.order_items
      set
        cancelled_quantity = cancelled_quantity + cancel_qty,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    end loop;
  end if;

  if not had_delivery
     and not exists (
       select 1
       from public.order_items oi
       where oi.order_id = o.id
         and oi.delivered_quantity > 0
     )
     and not exists (
       select 1
       from public.order_items oi
       where oi.order_id = o.id
         and (oi.quantity - oi.delivered_quantity - oi.cancelled_quantity) > 0
     ) then
    update public.orders
    set
      status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, timezone('utc', now())),
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;
    return;
  end if;

  update public.orders
  set
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.refresh_order_fulfillment_status(o.id);
end;
$$;

comment on function public.cancel_order_remaining(uuid, jsonb) is
  'Closes undelivered quantity and releases that reservation. Does not change on-hand stock.';

-- ---------------------------------------------------------------------------
-- mark_order_not_delivered — on-hand comes back and the order holds it again
-- ---------------------------------------------------------------------------

create or replace function public.mark_order_not_delivered(p_order_id uuid)
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
  put_back numeric(14, 3);
  any_delivered boolean := false;
  variant_ids uuid[];
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

  if o.status not in ('partially_delivered', 'completed') then
    raise exception 'This order is already not delivered.';
  end if;

  if exists (
    select 1
    from public.order_items oi
    where oi.order_id = o.id
      and oi.returned_quantity > 0
  ) then
    raise exception 'This order has returned items. Cancel that return on Orders, under Returns, then mark the order as not delivered.';
  end if;

  if exists (
    select 1
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = o.id
      and p.deleted_at is null
      and p.status = 'pending'
  ) then
    raise exception 'A payment on this order is still waiting for approval. Open Payments, approve or reject it, then mark the order as not delivered.';
  end if;

  select coalesce(array_agg(distinct oi.variant_id), '{}')
    into variant_ids
  from public.order_items oi
  where oi.order_id = o.id;

  perform public.lock_order_variant_stock(company, o.branch_id, variant_ids);

  for item in
    select * from public.order_items where order_id = o.id for update
  loop
    put_back := item.delivered_quantity;
    if put_back <= 0 then
      continue;
    end if;

    any_delivered := true;

    perform public.restock_and_rehold(
      o.branch_id,
      item.product_id,
      item.variant_id,
      put_back,
      o.id,
      'Marked as not delivered',
      o.order_number
    );

    update public.order_items
    set
      delivered_quantity = 0,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = item.id;
  end loop;

  if not any_delivered then
    raise exception 'This order is already not delivered.';
  end if;

  perform public.apply_order_fulfillment_receivable(o.id);

  update public.orders
  set
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.refresh_order_fulfillment_status(o.id);
end;
$$;

comment on function public.mark_order_not_delivered(uuid) is
  'Puts delivered units back on hand, reserves them for this order again, and returns the order to placed. Does not cancel the order or move payments.';

-- ---------------------------------------------------------------------------
-- cancel_sales_order — release undelivered holds; restock goods still with the customer
-- ---------------------------------------------------------------------------

create or replace function public.cancel_sales_order(
  p_order_id uuid,
  p_destination text default 'none',
  p_reason text default null
)
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
  fig record;
  reason text;
  destination text;
  paid_part numeric(14, 2);
  owed numeric(14, 2);
  put_back numeric(14, 3);
  open_hold numeric(14, 3);
  payment_no text;
  variant_ids uuid[];
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  reason := nullif(trim(coalesce(p_reason, '')), '');
  if reason is null then
    raise exception 'Write a short reason for cancelling this order.';
  end if;
  if char_length(reason) > 500 then
    raise exception 'Keep the reason shorter than 500 characters.';
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

  if o.status = 'cancelled' then
    return;
  end if;

  if o.status = 'draft' then
    update public.orders
    set
      status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, timezone('utc', now())),
      cancellation_reason = reason,
      cancellation_paid_destination = 'none',
      cancellation_paid_amount = 0,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;
    return;
  end if;

  if o.status not in ('placed', 'partially_delivered', 'completed') then
    raise exception 'This order cannot be cancelled.';
  end if;

  select * into fig from public._order_return_figures(o.id);

  if fig.approval_waiting then
    raise exception 'A payment on this order is still waiting for approval. Open Payments, approve or reject it, then cancel the order.';
  end if;

  paid_part := round(coalesce(fig.amount_paid, 0), 2);
  owed := greatest(
    round(coalesce(fig.still_owed, 0), 2),
    round(
      greatest(
        coalesce(o.recognized_receivable_value, 0) - coalesce(fig.amount_paid, 0),
        0
      ),
      2
    )
  );

  if paid_part > 0.001 and fig.cheque_waiting then
    raise exception 'A cheque on this order has not cleared yet. Finish it on Payments before cancelling. You can give the money back or add it to their wallet after that.';
  end if;

  destination := coalesce(nullif(trim(p_destination), ''), 'none');
  if paid_part <= 0.001 then
    destination := 'none';
    paid_part := 0;
  elsif destination not in ('cash', 'wallet') then
    raise exception 'Choose where the money they already paid goes.';
  end if;

  select coalesce(array_agg(distinct oi.variant_id), '{}')
    into variant_ids
  from public.order_items oi
  where oi.order_id = o.id;

  perform public.lock_order_variant_stock(company, o.branch_id, variant_ids);

  for item in
    select * from public.order_items where order_id = o.id for update
  loop
    open_hold := greatest(
      item.quantity - item.delivered_quantity - item.cancelled_quantity,
      0
    );
    perform public.apply_order_stock_hold(
      company,
      o.branch_id,
      item.variant_id,
      -open_hold,
      false
    );

    put_back := item.delivered_quantity - item.returned_quantity;
    if put_back > 0 then
      perform public.adjust_inventory(
        o.branch_id,
        item.product_id,
        put_back,
        'correction',
        'Order cancelled',
        o.order_number,
        'order',
        o.id,
        item.variant_id
      );
    end if;

    if item.returned_quantity <= 0 then
      update public.order_items
      set
        delivered_quantity = 0,
        cancelled_quantity = quantity,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    else
      update public.order_items
      set
        cancelled_quantity = quantity - delivered_quantity,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    end if;
  end loop;

  if owed > 0.001 then
    update public.customers
    set
      current_balance = greatest(current_balance - owed, 0),
      updated_by = emp
    where id = o.customer_id
      and company_id = company
      and deleted_at is null;
  end if;

  if destination = 'wallet' and paid_part > 0.001 then
    update public.customers
    set
      wallet_balance = wallet_balance + paid_part,
      updated_by = emp
    where id = o.customer_id
      and company_id = company
      and deleted_at is null;
  elsif destination = 'cash' and paid_part > 0.001 then
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
      refunded_at,
      created_by,
      updated_by
    )
    values (
      company,
      o.branch_id,
      o.customer_id,
      emp,
      payment_no,
      paid_part,
      'cash',
      'refunded',
      o.order_number,
      'Given back when ' || o.order_number || ' was cancelled',
      timezone('utc', now()),
      emp,
      emp
    );
  end if;

  update public.orders
  set
    status = 'cancelled',
    cancelled_at = coalesce(cancelled_at, timezone('utc', now())),
    cancellation_reason = reason,
    cancellation_paid_destination = destination,
    cancellation_paid_amount = paid_part,
    recognized_receivable_value = 0,
    payment_status = case
      when paid_part > 0.001 then 'refunded'
      else payment_status
    end,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;
end;
$$;

comment on function public.cancel_sales_order(uuid, text, text) is
  'Cancels a draft, placed, partially delivered, or completed order. Releases undelivered holds, restocks goods still with the customer, clears what they owe, and gives paid money back or adds it to the wallet.';

-- ---------------------------------------------------------------------------
-- cancel_order_return — do not pull units that are already held for another order
-- ---------------------------------------------------------------------------

create or replace function public.cancel_order_return(p_return_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  r public.order_returns%rowtype;
  o public.orders%rowtype;
  line record;
  item public.order_items%rowtype;
  wallet numeric(14, 2);
  on_hand numeric(14, 3);
  held numeric(14, 3);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into r
  from public.order_returns
  where id = p_return_id
    and deleted_at is null
  for update;

  if not found or r.company_id is distinct from company then
    raise exception 'Return not found.';
  end if;

  if r.status = 'cancelled' then
    raise exception 'This return is already cancelled.';
  end if;

  if timezone('Asia/Colombo', r.returned_at)::date
     is distinct from timezone('Asia/Colombo', now())::date then
    raise exception 'This return was recorded on an earlier day, so it cannot be cancelled.';
  end if;

  select * into o
  from public.orders
  where id = r.order_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if r.paid_destination = 'wallet' and r.paid_portion > 0.001 then
    select wallet_balance into wallet
    from public.customers
    where id = r.customer_id
      and company_id = company
      and deleted_at is null
    for update;

    if wallet is null or wallet + 0.001 < r.paid_portion then
      raise exception 'This return saved money for their next order, and some of it has already been used.';
    end if;
  end if;

  for line in
    select *
    from public.order_return_lines
    where return_id = r.id
  loop
    select * into item
    from public.order_items
    where id = line.order_item_id
    for update;

    if not found then
      raise exception 'Order line not found on this order.';
    end if;

    update public.order_items
    set
      returned_quantity = greatest(returned_quantity - line.quantity, 0),
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = item.id;

    if r.restock then
      select coalesce(i.quantity, 0), coalesce(i.reserved_quantity, 0)
        into on_hand, held
      from public.inventory i
      where i.company_id = company
        and i.branch_id = o.branch_id
        and i.variant_id = item.variant_id
      for update;

      if coalesce(on_hand, 0) - coalesce(held, 0) < line.quantity then
        raise exception 'These units have already been sold again, so the return cannot be cancelled.';
      end if;

      begin
        perform public.adjust_inventory(
          o.branch_id,
          item.product_id,
          -line.quantity,
          'correction',
          'Return cancelled ' || r.return_number,
          o.order_number,
          'order_return',
          r.id,
          item.variant_id
        );
      exception
        when others then
          if sqlerrm ilike '%insufficient stock%' then
            raise exception 'These units have already been sold again, so the return cannot be cancelled. Adjust the stock, then try again.';
          end if;
          raise;
      end;
    end if;
  end loop;

  update public.orders
  set
    recognized_receivable_value = public.order_delivered_financial_value(o.id),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  if r.owed_reduction > 0.001 then
    update public.customers
    set
      current_balance = current_balance + r.owed_reduction,
      updated_by = emp
    where id = r.customer_id
      and company_id = company
      and deleted_at is null;
  end if;

  if r.paid_destination = 'wallet' and r.paid_portion > 0.001 then
    update public.customers
    set
      wallet_balance = wallet_balance - r.paid_portion,
      updated_by = emp
    where id = r.customer_id
      and company_id = company
      and deleted_at is null;
  elsif r.payment_id is not null then
    update public.payments
    set
      status = 'cancelled',
      cancelled_at = timezone('utc', now()),
      updated_by = emp
    where id = r.payment_id
      and status = 'refunded'
      and deleted_at is null;
  end if;

  update public.order_returns
  set
    status = 'cancelled',
    cancelled_at = timezone('utc', now()),
    updated_by = emp
  where id = r.id;

  perform public.refresh_order_payment_status(o.id);
end;
$$;

comment on function public.cancel_order_return(uuid) is
  'Same-day undo of a return. Restores stock only when those units are not held for an open order, and restores outstanding and any cash or wallet settlement.';

-- ---------------------------------------------------------------------------
-- correct_invoice — adjust the open hold when lines change. On-hand moves only
-- for units that are already delivered or that a completed invoice sells now.
-- ---------------------------------------------------------------------------

create or replace function public.correct_invoice(
  p_order_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  o public.orders%rowtype;
  item public.order_items%rowtype;
  line jsonb;
  v_line_id uuid;
  v_product_id uuid;
  v_variant_id uuid;
  v_qty numeric(14, 3);
  v_unit_price numeric(14, 2);
  v_discount numeric(14, 2);
  v_discount_type text;
  v_line_total numeric(14, 2);
  v_subtotal numeric(14, 2) := 0;
  v_discount_percent numeric(14, 2);
  discount_fixed numeric(14, 2);
  resolved_discount numeric(14, 2);
  new_total numeric(14, 2);
  collected numeric(14, 2);
  pending_amount numeric(14, 2);
  new_customer uuid;
  old_customer uuid;
  recognized numeric(14, 2);
  seen uuid[] := '{}';
  new_delivered numeric(14, 3);
  deliver_delta numeric(14, 3);
  v_name text;
  v_sku text;
  v_label text;
  product_active boolean;
  sms_sent boolean := false;
  old_hold numeric(14, 3);
  new_hold numeric(14, 3);
  variant_ids uuid[];
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_correct_financials() then
    raise exception 'Only Owner or Manager can correct an invoice.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Invoice correction is missing its details.';
  end if;

  if jsonb_typeof(p_payload -> 'lines') <> 'array'
     or jsonb_array_length(p_payload -> 'lines') = 0 then
    raise exception 'Add at least one product before saving the correction.';
  end if;

  select * into o
  from public.orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if o.status = 'draft' then
    raise exception 'Save this from Edit draft. Invoice correction is for orders that have already been placed.';
  end if;

  if o.status = 'cancelled' then
    raise exception 'Cancelled invoices cannot be corrected.';
  end if;

  if exists (
    select 1
    from public.order_items oi
    where oi.order_id = o.id
      and oi.returned_quantity > 0
  ) then
    raise exception 'This invoice has returned items, so the prices cannot be changed. If the return was recorded today, cancel it on Orders, under Returns, then correct the invoice.';
  end if;

  if o.status not in ('placed', 'partially_delivered', 'completed') then
    raise exception 'This invoice cannot be corrected.';
  end if;

  select coalesce(sum(pa.amount), 0)
    into collected
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = o.id
    and p.deleted_at is null
    and p.status = 'completed';

  select coalesce(sum(pa.amount), 0)
    into pending_amount
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = o.id
    and p.deleted_at is null
    and p.status = 'pending';

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    v_qty := (line ->> 'quantity')::numeric;
    v_unit_price := (line ->> 'unit_price')::numeric;
    v_discount := nullif(line ->> 'discount', '')::numeric;
    v_discount_type := nullif(trim(line ->> 'discount_type'), '');
    if v_qty is null or v_qty <= 0 then
      raise exception 'Each product needs a quantity greater than zero.';
    end if;
    if v_unit_price is null or v_unit_price < 0 then
      raise exception 'Each product needs a price of zero or more.';
    end if;
    if v_discount_type is not null and v_discount_type not in ('percentage', 'fixed') then
      raise exception 'A line discount must be a percentage or a fixed amount.';
    end if;
    if v_discount_type = 'percentage' and coalesce(v_discount, 0) > 100 then
      raise exception 'A percentage discount cannot be more than 100.';
    end if;
    if v_discount is null or v_discount <= 0 or v_discount_type is null then
      v_discount := null;
      v_discount_type := null;
    end if;
    v_subtotal := v_subtotal + public._invoice_line_total(v_qty, v_unit_price, v_discount, v_discount_type);
  end loop;

  v_discount_percent := coalesce((p_payload ->> 'discount_percent')::numeric, 0);
  discount_fixed := coalesce((p_payload ->> 'discount_fixed_amount')::numeric, 0);
  if v_discount_percent < 0 then
    v_discount_percent := 0;
  end if;
  if v_discount_percent > 100 then
    v_discount_percent := 100;
  end if;
  if discount_fixed < 0 then
    discount_fixed := 0;
  end if;

  resolved_discount := round(v_subtotal * v_discount_percent / 100, 2);
  if discount_fixed > v_subtotal - resolved_discount then
    discount_fixed := v_subtotal - resolved_discount;
  end if;
  resolved_discount := resolved_discount + discount_fixed;
  new_total := round(v_subtotal - resolved_discount, 2);
  if coalesce(o.transportation_payer, 'seller') = 'receiver'
     and coalesce(o.transportation_cost, 0) > 0.001 then
    new_total := round(new_total + o.transportation_cost, 2);
  end if;
  if new_total <= 0 then
    raise exception 'Invoice total must be greater than zero.';
  end if;

  if new_total + 0.009 < collected + pending_amount then
    raise exception
      'This invoice already has % collected. It cannot be reduced below that until the collection is corrected.',
      trim(to_char(collected + pending_amount, 'FM999999990.00'));
  end if;

  new_customer := nullif(p_payload ->> 'customer_id', '')::uuid;
  if new_customer is null then
    raise exception 'Choose a customer for this invoice.';
  end if;

  if new_customer is distinct from o.customer_id
     and collected + pending_amount > 0 then
    raise exception
      'This invoice already has a collection. Correct or cancel that payment before changing the customer.';
  end if;

  if new_customer is distinct from o.customer_id then
    if not exists (
      select 1 from public.customers c
      where c.id = new_customer
        and c.company_id = company
        and c.deleted_at is null
        and c.is_active = true
    ) then
      raise exception 'Customer not found.';
    end if;

    old_customer := o.customer_id;
    recognized := coalesce(o.recognized_receivable_value, 0);

    update public.customers
    set
      current_balance = greatest(current_balance - recognized, 0),
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = old_customer
      and company_id = company;

    update public.orders
    set
      customer_id = new_customer,
      recognized_receivable_value = 0,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;

    select * into o from public.orders where id = o.id for update;
  end if;

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    v_line_id := nullif(line ->> 'id', '')::uuid;
    if v_line_id is not null then
      seen := array_append(seen, v_line_id);
    end if;
  end loop;


  select coalesce(array_agg(distinct vid), '{}')
    into variant_ids
  from (
    select oi.variant_id as vid
    from public.order_items oi
    where oi.order_id = o.id
      and oi.variant_id is not null
    union
    select nullif(elem->>'variant_id', '')::uuid
    from jsonb_array_elements(p_payload -> 'lines') elem
  ) s
  where vid is not null;

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    if nullif(line ->> 'variant_id', '') is null
       and nullif(line ->> 'product_id', '') is not null then
      variant_ids := variant_ids || array[
        (public.resolve_default_product_variant(
          company,
          (line ->> 'product_id')::uuid
        )).id
      ];
    end if;
  end loop;

  perform public.lock_order_variant_stock(company, o.branch_id, variant_ids);

  for item in
    select * from public.order_items
    where order_id = o.id
      and not (id = any (seen))
    for update
  loop
    if o.status in ('placed', 'partially_delivered') then
      perform public.apply_order_stock_hold(
        company,
        o.branch_id,
        item.variant_id,
        -greatest(item.quantity - item.delivered_quantity - item.cancelled_quantity, 0),
        false
      );
    end if;
    if item.delivered_quantity > 0 then
      perform public.adjust_inventory(
        o.branch_id,
        item.product_id,
        item.delivered_quantity,
        'return',
        'Invoice correction',
        null,
        'order',
        o.id,
        item.variant_id
      );
    end if;
    delete from public.order_items where id = item.id;
  end loop;

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    v_line_id := nullif(line ->> 'id', '')::uuid;
    v_product_id := (line ->> 'product_id')::uuid;
    v_variant_id := nullif(line ->> 'variant_id', '')::uuid;
    v_qty := (line ->> 'quantity')::numeric;
    v_unit_price := round((line ->> 'unit_price')::numeric, 2);
    v_discount := nullif(line ->> 'discount', '')::numeric;
    v_discount_type := nullif(trim(line ->> 'discount_type'), '');
    if v_discount is null or v_discount <= 0 or v_discount_type is null then
      v_discount := null;
      v_discount_type := null;
    end if;
    v_line_total := public._invoice_line_total(v_qty, v_unit_price, v_discount, v_discount_type);

    if v_product_id is null then
      raise exception 'Each product on the invoice must be identified.';
    end if;

    select p.is_active
      into product_active
    from public.products p
    where p.id = v_product_id
      and p.company_id = company
      and p.deleted_at is null;

    if product_active is null then
      raise exception 'A product on this invoice is no longer available.';
    end if;

    if v_variant_id is null then
      v_variant_id := (public.resolve_default_product_variant(company, v_product_id)).id;
    end if;

    if v_line_id is null then
      if product_active is not true then
        raise exception 'That product is no longer for sale.';
      end if;

      new_delivered := case when o.status = 'completed' then v_qty else 0 end;
      if o.status in ('placed', 'partially_delivered') then
        perform public.apply_order_stock_hold(
          company,
          o.branch_id,
          v_variant_id,
          v_qty,
          false
        );
      end if;
      if new_delivered > 0 then
        perform public.assert_order_line_stock_available(
          company, o.branch_id, v_variant_id, new_delivered
        );
        perform public.adjust_inventory(
          o.branch_id,
          v_product_id,
          -new_delivered,
          'sale',
          'Invoice correction',
          null,
          'order',
          o.id,
          v_variant_id
        );
      end if;

      insert into public.order_items (
        company_id,
        order_id,
        product_id,
        variant_id,
        quantity,
        unit_price,
        discount,
        discount_type,
        line_total,
        delivered_quantity,
        cancelled_quantity,
        created_by,
        updated_by
      ) values (
        company,
        o.id,
        v_product_id,
        v_variant_id,
        v_qty,
        v_unit_price,
        v_discount,
        v_discount_type,
        v_line_total,
        new_delivered,
        0,
        emp,
        emp
      );
    else
      select * into item
      from public.order_items
      where id = v_line_id
        and order_id = o.id
      for update;

      if not found then
        raise exception 'A product line on this invoice could not be found.';
      end if;

      if product_active is not true and item.product_id is distinct from v_product_id then
        raise exception 'That product is no longer for sale.';
      end if;

      if v_qty < item.cancelled_quantity then
        raise exception 'Quantity cannot be lower than the amount already cancelled on that line.';
      end if;

      if o.status = 'completed' then
        new_delivered := v_qty - item.cancelled_quantity;
      else
        new_delivered := least(item.delivered_quantity, v_qty - item.cancelled_quantity);
      end if;

      if item.variant_id is distinct from v_variant_id
         or item.product_id is distinct from v_product_id then
        if o.status in ('placed', 'partially_delivered') then
          perform public.apply_order_stock_hold(
            company,
            o.branch_id,
            item.variant_id,
            -greatest(item.quantity - item.delivered_quantity - item.cancelled_quantity, 0),
            false
          );
        end if;
        if item.delivered_quantity > 0 then
          perform public.adjust_inventory(
            o.branch_id,
            item.product_id,
            item.delivered_quantity,
            'return',
            'Invoice correction',
            null,
            'order',
            o.id,
            item.variant_id
          );
        end if;
        if o.status in ('placed', 'partially_delivered') then
          perform public.apply_order_stock_hold(
            company,
            o.branch_id,
            v_variant_id,
            greatest(v_qty - new_delivered - item.cancelled_quantity, 0),
            false
          );
        end if;
        if new_delivered > 0 then
          perform public.assert_order_line_stock_available(
            company, o.branch_id, v_variant_id, new_delivered
          );
          perform public.adjust_inventory(
            o.branch_id,
            v_product_id,
            -new_delivered,
            'sale',
            'Invoice correction',
            null,
            'order',
            o.id,
            v_variant_id
          );
        end if;
      else
        if o.status in ('placed', 'partially_delivered') then
          old_hold := greatest(item.quantity - item.delivered_quantity - item.cancelled_quantity, 0);
          new_hold := greatest(v_qty - new_delivered - item.cancelled_quantity, 0);
          perform public.apply_order_stock_hold(
            company,
            o.branch_id,
            v_variant_id,
            new_hold - old_hold,
            false
          );
        end if;
        deliver_delta := new_delivered - item.delivered_quantity;
        if deliver_delta > 0 then
          perform public.assert_order_line_stock_available(
            company, o.branch_id, v_variant_id, deliver_delta
          );
          perform public.adjust_inventory(
            o.branch_id,
            v_product_id,
            -deliver_delta,
            'sale',
            'Invoice correction',
            null,
            'order',
            o.id,
            v_variant_id
          );
        elsif deliver_delta < 0 then
          perform public.adjust_inventory(
            o.branch_id,
            v_product_id,
            -deliver_delta,
            'return',
            'Invoice correction',
            null,
            'order',
            o.id,
            v_variant_id
          );
        end if;
      end if;

      select p.name, v.sku, nullif(trim(coalesce(v.label, '')), '')
        into v_name, v_sku, v_label
      from public.product_variants v
      join public.products p on p.id = v.product_id
      where v.id = v_variant_id
        and v.company_id = company;

      update public.order_items
      set
        product_id = v_product_id,
        variant_id = v_variant_id,
        quantity = v_qty,
        unit_price = v_unit_price,
        discount = v_discount,
        discount_type = v_discount_type,
        line_total = v_line_total,
        delivered_quantity = new_delivered,
        product_name = case
          when item.variant_id is distinct from v_variant_id
            or item.product_id is distinct from v_product_id
          then coalesce(nullif(trim(v_name), ''), product_name)
          else product_name
        end,
        sku = case
          when item.variant_id is distinct from v_variant_id
            or item.product_id is distinct from v_product_id
          then v_sku
          else sku
        end,
        variant_label = case
          when item.variant_id is distinct from v_variant_id
            or item.product_id is distinct from v_product_id
          then v_label
          else variant_label
        end,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    end if;
  end loop;

  update public.orders
  set
    payment_method = case
      when collected + pending_amount > 0 then payment_method
      else coalesce(nullif(trim(p_payload ->> 'payment_method'), ''), payment_method)
    end,
    notes = nullif(trim(p_payload ->> 'notes'), ''),
    subtotal = v_subtotal,
    discount_percent = v_discount_percent,
    discount_fixed_amount = discount_fixed,
    discount_amount = resolved_discount,
    total = new_total,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.refresh_order_fulfillment_status(o.id);
  perform public.apply_order_fulfillment_receivable(o.id);
  perform public.refresh_order_payment_status(o.id);

  select exists (
    select 1
    from public.outbound_notification_events e
    join public.outbound_notification_dispatches d on d.event_id = e.id
    where e.company_id = company
      and e.event_type = 'order_confirmation'
      and e.reference_type = 'order'
      and e.reference_id = o.id
      and d.channel = 'sms'
      and d.recipient_kind = 'customer'
      and d.status = 'sent'
  )
  into sms_sent;

  perform public.log_company_activity(
    company,
    'orders',
    'invoice_corrected',
    'Invoice ' || o.order_number || ' corrected',
    emp,
    null,
    'order',
    o.id,
    jsonb_build_object(
      'order_number', o.order_number,
      'total', new_total
    )
  );

  return jsonb_build_object(
    'order_id', o.id,
    'order_number', o.order_number,
    'sms_previously_sent', sms_sent
  );
end;
$$;


comment on function public.correct_invoice(uuid, jsonb) is
  'Owner/Manager correction of a placed, partial, or completed invoice. '
  'Adjusts the open reservation and on-hand stock for delivered units, and '
  'refreshes the receivable while preserving the invoice number and document link.';
