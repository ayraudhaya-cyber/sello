-- V1 operational notifications: dedupe + emit from place / fulfill / adjust RPCs.
-- Extends existing notifications inbox (024). Does not rewrite history.

-- ---------------------------------------------------------------------------
-- Dedupe key (event identity — not continuous state)
-- ---------------------------------------------------------------------------

alter table public.notifications
  add column if not exists dedupe_key text;

comment on column public.notifications.dedupe_key is
  'Optional event identity for idempotent emits (e.g. order_placed:<order_id>).';

create unique index if not exists notifications_company_recipient_dedupe_uidx
  on public.notifications (company_id, recipient_employee_id, dedupe_key)
  where dedupe_key is not null and deleted_at is null;

-- ---------------------------------------------------------------------------
-- emit_notification — optional dedupe (drop/recreate to add parameter)
-- ---------------------------------------------------------------------------

drop function if exists public.emit_notification(
  uuid, uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb
);

create or replace function public.emit_notification(
  p_company_id uuid,
  p_recipient_employee_id uuid,
  p_category text,
  p_type text,
  p_title text,
  p_body text default null,
  p_priority text default 'normal',
  p_actor_employee_id uuid default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_route_hint text default null,
  p_payload jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  prefer_in_app boolean := true;
  dedupe text := nullif(trim(coalesce(p_dedupe_key, '')), '');
begin
  if p_company_id is null or p_recipient_employee_id is null then
    raise exception 'company and recipient are required';
  end if;

  if dedupe is not null and exists (
    select 1
    from public.notifications n
    where n.company_id = p_company_id
      and n.recipient_employee_id = p_recipient_employee_id
      and n.dedupe_key = dedupe
      and n.deleted_at is null
  ) then
    return null;
  end if;

  select coalesce(np.channel_in_app, true)
  into prefer_in_app
  from public.notification_preferences np
  where np.employee_id = p_recipient_employee_id
    and np.category = p_category
  limit 1;

  if prefer_in_app is false then
    return null;
  end if;

  insert into public.notifications (
    company_id,
    recipient_employee_id,
    actor_employee_id,
    category,
    type,
    priority,
    title,
    body,
    reference_type,
    reference_id,
    route_hint,
    payload,
    dedupe_key
  ) values (
    p_company_id,
    p_recipient_employee_id,
    p_actor_employee_id,
    p_category,
    p_type,
    coalesce(nullif(trim(p_priority), ''), 'normal'),
    trim(p_title),
    nullif(trim(p_body), ''),
    p_reference_type,
    p_reference_id,
    nullif(trim(p_route_hint), ''),
    coalesce(p_payload, '{}'::jsonb),
    dedupe
  )
  returning id into new_id;

  return new_id;
exception
  when unique_violation then
    return null;
end;
$$;

comment on function public.emit_notification is
  'Insert one in-app notification. Honors preferences and optional dedupe_key.';

drop function if exists public.emit_notifications_for_hub_roles(
  uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb, uuid
);

create or replace function public.emit_notifications_for_hub_roles(
  p_company_id uuid,
  p_category text,
  p_type text,
  p_title text,
  p_body text default null,
  p_priority text default 'normal',
  p_actor_employee_id uuid default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_route_hint text default null,
  p_payload jsonb default '{}'::jsonb,
  p_exclude_employee_id uuid default null,
  p_dedupe_key text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer := 0;
  rec record;
begin
  for rec in
    select e.id
    from public.employees e
    join public.roles r on r.id = e.role_id
    where e.company_id = p_company_id
      and e.deleted_at is null
      and e.employment_status = 'active'
      and r.code in ('owner', 'manager')
      and (p_exclude_employee_id is null or e.id <> p_exclude_employee_id)
  loop
    if public.emit_notification(
      p_company_id,
      rec.id,
      p_category,
      p_type,
      p_title,
      p_body,
      p_priority,
      p_actor_employee_id,
      p_reference_type,
      p_reference_id,
      p_route_hint,
      p_payload,
      p_dedupe_key
    ) is not null then
      inserted := inserted + 1;
    end if;
  end loop;

  return inserted;
end;
$$;

comment on function public.emit_notifications_for_hub_roles is
  'Notify active Owners/Managers. Optional dedupe_key prevents duplicate events.';

revoke all on function public.emit_notification(
  uuid, uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb, text
) from public;
grant execute on function public.emit_notification(
  uuid, uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb, text
) to authenticated;

revoke all on function public.emit_notifications_for_hub_roles(
  uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb, uuid, text
) from public;
grant execute on function public.emit_notifications_for_hub_roles(
  uuid, text, text, text, text, text, uuid, text, uuid, text, jsonb, uuid, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- place_sales_order — demand only + Hub notifications
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
  avail numeric(14, 3);
  on_hand numeric(14, 3);
  reserved numeric(14, 3);
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

  -- Detect insufficient available stock for the insufficient-stock notification.
  -- Uses current available (on-hand − reserved), not a historical snapshot.
  for item in
    select * from public.order_items where order_id = o.id
  loop
    select i.quantity, coalesce(i.reserved_quantity, 0)
      into on_hand, reserved
    from public.inventory i
    where i.company_id = company
      and i.branch_id = o.branch_id
      and i.product_id = item.product_id;

    if not found then
      on_hand := 0;
      reserved := 0;
    end if;

    avail := on_hand - reserved;
    if avail < 0 then
      avail := 0;
    end if;

    if item.quantity > avail then
      insufficient := true;
      exit;
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
  'Marks draft as placed. No inventory/payment. Notifies Hub of place (+ insufficient stock when needed).';

revoke all on function public.place_sales_order(uuid) from public;
grant execute on function public.place_sales_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- fulfill_order_items — inventory + AR + partial-delivery notification
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
  'Delivers listed quantities, deducts inventory, recognizes AR, notifies on first partial.';

revoke all on function public.fulfill_order_items(uuid, jsonb) from public;
grant execute on function public.fulfill_order_items(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- adjust_inventory — notify only when crossing into negative stock
-- ---------------------------------------------------------------------------

create or replace function public.adjust_inventory(
  p_branch_id uuid,
  p_product_id uuid,
  p_quantity_delta numeric,
  p_movement_type text,
  p_reason text default null,
  p_notes text default null,
  p_reference_type text default null,
  p_reference_id uuid default null
)
returns public.inventory
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  allow_neg boolean := false;
  inv public.inventory%rowtype;
  new_qty numeric(14, 3);
  qty_before numeric(14, 3);
  movement_id uuid;
  product_name text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Quantity change must be non-zero.';
  end if;

  if p_movement_type not in (
    'purchase', 'sale', 'damage', 'return', 'correction', 'transfer', 'adjustment'
  ) then
    raise exception 'Unsupported movement type.';
  end if;

  select coalesce(cs.allow_negative_stock, false)
    into allow_neg
  from public.company_settings cs
  where cs.company_id = company;

  insert into public.inventory (
    company_id,
    branch_id,
    product_id,
    quantity,
    created_by,
    updated_by
  )
  values (
    company,
    p_branch_id,
    p_product_id,
    0,
    emp,
    emp
  )
  on conflict (company_id, branch_id, product_id) do nothing;

  select * into inv
  from public.inventory
  where company_id = company
    and branch_id = p_branch_id
    and product_id = p_product_id
  for update;

  if not found then
    raise exception 'Inventory row not found.';
  end if;

  qty_before := inv.quantity;
  new_qty := inv.quantity + p_quantity_delta;

  if new_qty < 0 and not allow_neg then
    raise exception 'Insufficient stock for this adjustment.';
  end if;

  update public.inventory
  set
    quantity = new_qty,
    last_movement_at = timezone('utc', now()),
    updated_by = emp
  where id = inv.id
  returning * into inv;

  insert into public.stock_movements (
    company_id,
    branch_id,
    product_id,
    movement_type,
    quantity_delta,
    quantity_after,
    reason,
    notes,
    reference_type,
    reference_id,
    created_by
  )
  values (
    company,
    p_branch_id,
    p_product_id,
    p_movement_type,
    p_quantity_delta,
    new_qty,
    nullif(trim(coalesce(p_reason, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    p_reference_type,
    p_reference_id,
    emp
  )
  returning id into movement_id;

  if qty_before >= 0 and new_qty < 0 then
    select coalesce(nullif(trim(p.name), ''), 'Product')
      into product_name
    from public.products p
    where p.id = p_product_id;

    perform public.emit_notifications_for_hub_roles(
      company,
      'inventory',
      'negative_stock',
      'Negative stock',
      product_name || ' is now below zero stock.',
      'high',
      emp,
      'product',
      p_product_id,
      '/hub/inventory',
      jsonb_build_object(
        'branch_id', p_branch_id,
        'quantity_after', new_qty
      ),
      emp,
      'negative_stock:' || movement_id::text
    );
  end if;

  return inv;
end;
$$;

revoke all on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid
) from public;
grant execute on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid
) to authenticated;
