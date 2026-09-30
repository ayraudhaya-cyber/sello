-- =============================================================================
-- 087 — Sales Rep record-delivery setting
--
-- Owner/Manager can turn off Sales Rep Record delivery / Deliver remaining.
-- Default true keeps current behaviour. Owner, Manager, and other Hub roles
-- are never gated. Enforced in fulfill_order_items and complete_sales_order.
-- =============================================================================

alter table public.company_settings
  add column if not exists sales_reps_can_record_delivery
    boolean not null default true;

comment on column public.company_settings.sales_reps_can_record_delivery is
  'When true, Sales Representatives may record delivery. When false, only Owner/Manager can.';

create or replace function public.can_record_order_delivery()
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
        select cs.sales_reps_can_record_delivery
        from public.company_settings cs
        where cs.company_id = public.current_company_id()
      ),
      true
    );
$$;

comment on function public.can_record_order_delivery() is
  'False only for Sales Representatives when the company has turned off Sales delivery.';

revoke all on function public.can_record_order_delivery() from public;
grant execute on function public.can_record_order_delivery() to authenticated;

-- ---------------------------------------------------------------------------
-- fulfill_order_items — same as 074, plus delivery permission gate
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

    perform public.assert_order_line_stock_available(
      company,
      o.branch_id,
      item.variant_id,
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
      o.id,
      item.variant_id
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
  'Delivers listed quantities, deducts variant inventory, recognizes AR, notifies on first partial. Sales Reps require sales_reps_can_record_delivery.';

revoke all on function public.fulfill_order_items(uuid, jsonb) from public;
grant execute on function public.fulfill_order_items(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- complete_sales_order — same as 074, plus delivery permission gate
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

    if item.variant_id is null then
      raise exception 'Order line missing variant_id.';
    end if;

    perform public.assert_order_line_stock_available(
      company,
      o.branch_id,
      item.variant_id,
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
      o.id,
      item.variant_id
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
  'Fulfills remaining quantity by variant_id, recognizes unpaid delivered AR, marks completed. Sales Reps require sales_reps_can_record_delivery.';

revoke all on function public.complete_sales_order(uuid) from public;
grant execute on function public.complete_sales_order(uuid) to authenticated;
