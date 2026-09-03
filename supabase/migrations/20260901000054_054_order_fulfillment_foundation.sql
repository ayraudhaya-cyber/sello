-- Order fulfillment foundation: demand vs delivered vs cancelled, progressive stock.

-- ---------------------------------------------------------------------------
-- Status: draft | placed | partially_delivered | completed | cancelled
-- (migrate unused 'submitted' → 'placed')
-- ---------------------------------------------------------------------------

update public.orders
set status = 'placed'
where status = 'submitted'
  and deleted_at is null;

alter table public.orders
  drop constraint if exists orders_status_allowed;

alter table public.orders
  add constraint orders_status_allowed check (
    status in (
      'draft',
      'placed',
      'partially_delivered',
      'completed',
      'cancelled'
    )
  );

comment on column public.orders.status is
  'draft | placed | partially_delivered | completed | cancelled. '
  'completed means fulfillment is finished (delivered + cancelled cover ordered qty).';

comment on column public.orders.submitted_at is
  'When the order left draft and became placed (demand recorded).';

-- ---------------------------------------------------------------------------
-- Line-level fulfillment quantities
-- quantity = ordered demand
-- delivered_quantity = actually fulfilled (inventory deducted for this amount)
-- cancelled_quantity = closed without delivery
-- remaining = quantity - delivered - cancelled (derived)
-- ---------------------------------------------------------------------------

alter table public.order_items
  add column if not exists delivered_quantity numeric(14, 3) not null default 0;

alter table public.order_items
  add column if not exists cancelled_quantity numeric(14, 3) not null default 0;

alter table public.order_items
  drop constraint if exists order_items_fulfillment_bounds;

alter table public.order_items
  add constraint order_items_fulfillment_bounds check (
    delivered_quantity >= 0
    and cancelled_quantity >= 0
    and delivered_quantity + cancelled_quantity <= quantity
  );

comment on column public.order_items.quantity is
  'Ordered / requested quantity (customer demand).';

comment on column public.order_items.delivered_quantity is
  'Cumulative quantity actually fulfilled. Inventory is deducted only for this.';

comment on column public.order_items.cancelled_quantity is
  'Cumulative quantity closed without delivery. Does not affect inventory.';

-- Existing completed orders: treat ordered qty as fully delivered.
update public.order_items oi
set
  delivered_quantity = oi.quantity,
  cancelled_quantity = 0
from public.orders o
where oi.order_id = o.id
  and o.status = 'completed'
  and oi.delivered_quantity = 0
  and oi.cancelled_quantity = 0;

-- Existing cancelled with no delivery: treat ordered qty as cancelled.
update public.order_items oi
set
  delivered_quantity = 0,
  cancelled_quantity = oi.quantity
from public.orders o
where oi.order_id = o.id
  and o.status = 'cancelled'
  and oi.delivered_quantity = 0
  and oi.cancelled_quantity = 0;

-- ---------------------------------------------------------------------------
-- Status helper from line remaining
-- ---------------------------------------------------------------------------

create or replace function public.refresh_order_fulfillment_status(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  has_delivery boolean;
  has_remaining boolean;
begin
  select * into o
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if o.status in ('draft', 'cancelled') then
    return;
  end if;

  select
    exists (
      select 1
      from public.order_items oi
      where oi.order_id = o.id
        and oi.delivered_quantity > 0
    ),
    exists (
      select 1
      from public.order_items oi
      where oi.order_id = o.id
        and (oi.quantity - oi.delivered_quantity - oi.cancelled_quantity) > 0
    )
  into has_delivery, has_remaining;

  if not has_remaining then
    update public.orders
    set
      status = 'completed',
      completed_at = coalesce(completed_at, timezone('utc', now())),
      updated_at = timezone('utc', now())
    where id = o.id;
  elsif has_delivery then
    update public.orders
    set
      status = 'partially_delivered',
      completed_at = null,
      updated_at = timezone('utc', now())
    where id = o.id;
  else
    update public.orders
    set
      status = 'placed',
      completed_at = null,
      updated_at = timezone('utc', now())
    where id = o.id;
  end if;
end;
$$;

revoke all on function public.refresh_order_fulfillment_status(uuid) from public;
grant execute on function public.refresh_order_fulfillment_status(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Shared stock check for a delivery quantity
-- ---------------------------------------------------------------------------

create or replace function public.assert_order_line_stock_available(
  p_company_id uuid,
  p_branch_id uuid,
  p_product_id uuid,
  p_quantity numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  allow_above boolean := false;
  on_hand numeric(14, 3);
  reserved numeric(14, 3);
  available numeric(14, 3);
  product_name text;
begin
  if p_quantity is null or p_quantity <= 0 then
    return;
  end if;

  select coalesce(cs.allow_orders_above_available_stock, false)
    into allow_above
  from public.company_settings cs
  where cs.company_id = p_company_id;

  if allow_above then
    return;
  end if;

  select
    coalesce(i.quantity, 0),
    coalesce(i.reserved_quantity, 0)
  into on_hand, reserved
  from public.inventory i
  where i.company_id = p_company_id
    and i.branch_id = p_branch_id
    and i.product_id = p_product_id;

  available := coalesce(on_hand, 0) - coalesce(reserved, 0);
  if available < 0 then
    available := 0;
  end if;

  if p_quantity > available then
    select p.name into product_name
    from public.products p
    where p.id = p_product_id
      and p.company_id = p_company_id;

    raise exception
      'Not enough stock for %. Only % available.',
      coalesce(product_name, 'product'),
      available;
  end if;
end;
$$;

revoke all on function public.assert_order_line_stock_available(uuid, uuid, uuid, numeric)
  from public;
grant execute on function public.assert_order_line_stock_available(uuid, uuid, uuid, numeric)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Financial settlement (place or same-day complete) — no inventory
-- ---------------------------------------------------------------------------

create or replace function public.settle_sales_order_payment(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  customer_row public.customers%rowtype;
  method text;
  payment_id uuid;
  payment_no text;
  settle boolean := false;
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

  -- Settlement runs once while the order is still draft (place / same-day complete).
  if o.status <> 'draft' then
    return;
  end if;

  if o.payment_status = 'paid' then
    return;
  end if;

  select * into customer_row
  from public.customers
  where id = o.customer_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Customer not found.';
  end if;

  method := coalesce(o.payment_method, '');
  settle := method in ('cash', 'card', 'bank_transfer', 'wallet');

  if method = 'wallet' and customer_row.wallet_balance < o.total then
    raise exception 'Insufficient wallet balance.';
  end if;

  if method = 'credit' and coalesce(customer_row.credit_allowed, false) is not true then
    raise exception 'This customer is not allowed to buy on credit.';
  end if;

  if settle then
    update public.orders
    set
      payment_status = 'paid',
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;

    if method = 'wallet' then
      update public.customers
      set
        wallet_balance = wallet_balance - o.total,
        last_purchase_at = greatest(
          coalesce(last_purchase_at, o.ordered_at),
          coalesce(o.ordered_at, timezone('utc', now()))
        ),
        updated_by = emp
      where id = o.customer_id;
    else
      update public.customers
      set
        last_purchase_at = greatest(
          coalesce(last_purchase_at, o.ordered_at),
          coalesce(o.ordered_at, timezone('utc', now()))
        ),
        updated_by = emp
      where id = o.customer_id;
    end if;

    if not exists (
      select 1
      from public.payment_allocations pa
      join public.payments p on p.id = pa.payment_id
      where pa.order_id = o.id
        and p.deleted_at is null
        and p.status = 'completed'
    ) then
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
        notes,
        created_by,
        updated_by
      ) values (
        company,
        o.branch_id,
        o.customer_id,
        emp,
        payment_no,
        o.total,
        method,
        'completed',
        'Recorded on order placement',
        emp,
        emp
      )
      returning id into payment_id;

      insert into public.payment_allocations (
        company_id,
        payment_id,
        order_id,
        amount,
        created_by,
        updated_by
      ) values (
        company,
        payment_id,
        o.id,
        o.total,
        emp,
        emp
      );
    end if;
  else
    update public.orders
    set
      payment_status = 'unpaid',
      payment_method = coalesce(nullif(method, ''), 'credit'),
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;

    update public.customers
    set
      current_balance = current_balance + o.total,
      last_purchase_at = greatest(
        coalesce(last_purchase_at, o.ordered_at),
        coalesce(o.ordered_at, timezone('utc', now()))
      ),
      updated_by = emp
    where id = o.customer_id;
  end if;
end;
$$;

revoke all on function public.settle_sales_order_payment(uuid) from public;
grant execute on function public.settle_sales_order_payment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- place_sales_order: draft → placed (demand + payment). No inventory.
-- ---------------------------------------------------------------------------

create or replace function public.place_sales_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
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

  perform public.settle_sales_order_payment(p_order_id);

  update public.orders
  set
    status = 'placed',
    submitted_at = coalesce(submitted_at, timezone('utc', now())),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_order_id;
end;
$$;

revoke all on function public.place_sales_order(uuid) from public;
grant execute on function public.place_sales_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- fulfill_order_items: deliver quantities; deduct inventory once per unit
-- p_lines: [{"order_item_id":"<uuid>","quantity":12}]
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

  update public.orders
  set
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.refresh_order_fulfillment_status(o.id);
end;
$$;

revoke all on function public.fulfill_order_items(uuid, jsonb) from public;
grant execute on function public.fulfill_order_items(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- cancel_order_remaining: close outstanding demand without inventory impact
-- p_lines null → cancel all remaining; else per-line cancel quantities
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

  if p_lines is null then
    for item in
      select * from public.order_items where order_id = o.id for update
    loop
      remaining := item.quantity - item.delivered_quantity - item.cancelled_quantity;
      if remaining > 0 then
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

      update public.order_items
      set
        cancelled_quantity = cancelled_quantity + cancel_qty,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    end loop;
  end if;

  -- No deliveries ever → full cancel of demand → cancelled order
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

revoke all on function public.cancel_order_remaining(uuid, jsonb) from public;
grant execute on function public.cancel_order_remaining(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- complete_sales_order: same-day / finish path (Sales UX preserved)
-- draft → settle + deliver all remaining → completed
-- placed | partially_delivered → deliver all remaining → completed (no re-settle)
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
    perform public.settle_sales_order_payment(p_order_id);

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

revoke all on function public.complete_sales_order(uuid) from public;
grant execute on function public.complete_sales_order(uuid) to authenticated;

-- archive_order: still only completed / cancelled (reject open fulfillment)
create or replace function public.archive_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into o
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if o.company_id is distinct from company then
    raise exception 'Forbidden.';
  end if;

  if o.deleted_at is not null then
    return;
  end if;

  if o.status in ('draft', 'placed', 'partially_delivered') then
    raise exception 'Cancel open orders instead of archiving them.';
  end if;

  update public.orders
  set
    deleted_at = timezone('utc', now()),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;
end;
$$;

revoke all on function public.archive_order(uuid) from public;
grant execute on function public.archive_order(uuid) to authenticated;
