-- =============================================================================
-- 074 — Product variants Phase E: variant-aware inventory + order RPCs
--
-- Makes inventory mutation and order place/fulfill/complete operate by
-- order_items.variant_id / inventory.variant_id while keeping product_id as the
-- parent/catalog reference.
--
-- Compatibility (no Flutter changes in this phase):
--   - adjust_inventory keeps (p_branch_id, p_product_id, ...) signature and
--     resolves the live default variant when p_variant_id is omitted.
--   - Optional trailing p_variant_id lets fulfillment pass the line's variant.
--   - BEFORE INSERT triggers fill order_items / inventory variant + snapshots
--     when the deployed app still inserts by product_id only.
--   - AFTER INSERT on products creates the default variant (Phase B shape).
--   - Partial unique on (company, branch, product) WHERE is_default_variant
--     preserves Flutter inventory upsert ON CONFLICT until Phase F.
--
-- Does NOT modify Flutter, products catalog columns, historical movement values,
-- or historical order_item financial/snapshot values.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

do $guard$
declare
  missing_defaults integer;
  multi_defaults integer;
  inv_null_variant integer;
  inv_mismatch integer;
  oi_null_variant integer;
  oi_mismatch integer;
begin
  select count(*)::int into missing_defaults
  from public.products p
  where not exists (
    select 1
    from public.product_variants v
    where v.product_id = p.id
      and v.is_default = true
      and v.deleted_at is null
  );

  if missing_defaults > 0 then
    raise exception
      'Phase E aborted: % product(s) lack a non-deleted default variant',
      missing_defaults;
  end if;

  select count(*)::int into multi_defaults
  from (
    select product_id
    from public.product_variants
    where is_default = true
      and deleted_at is null
    group by product_id
    having count(*) > 1
  ) d;

  if multi_defaults > 0 then
    raise exception
      'Phase E aborted: % product(s) have multiple non-deleted defaults',
      multi_defaults;
  end if;

  select count(*)::int into inv_null_variant
  from public.inventory
  where variant_id is null;

  if inv_null_variant > 0 then
    raise exception
      'Phase E aborted: % inventory row(s) missing variant_id',
      inv_null_variant;
  end if;

  select count(*)::int into inv_mismatch
  from public.inventory i
  join public.product_variants v on v.id = i.variant_id
  where v.product_id is distinct from i.product_id
     or v.company_id is distinct from i.company_id;

  if inv_mismatch > 0 then
    raise exception
      'Phase E aborted: % inventory row(s) have mismatched variant/product/company',
      inv_mismatch;
  end if;

  select count(*)::int into oi_null_variant
  from public.order_items
  where variant_id is null;

  if oi_null_variant > 0 then
    raise exception
      'Phase E aborted: % order_item row(s) missing variant_id',
      oi_null_variant;
  end if;

  select count(*)::int into oi_mismatch
  from public.order_items oi
  join public.product_variants v on v.id = oi.variant_id
  where v.product_id is distinct from oi.product_id
     or v.company_id is distinct from oi.company_id;

  if oi_mismatch > 0 then
    raise exception
      'Phase E aborted: % order_item row(s) have mismatched variant/product/company',
      oi_mismatch;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.inventory'::regclass
      and conname = 'inventory_company_branch_variant_key'
  ) then
    raise exception
      'Phase E aborted: inventory_company_branch_variant_key missing';
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------------
-- Compat column: default-variant inventory rows (Flutter upsert ON CONFLICT)
-- ---------------------------------------------------------------------------

alter table public.inventory
  add column if not exists is_default_variant boolean not null default false;

comment on column public.inventory.is_default_variant is
  'Denormalized from product_variants.is_default. Enables temporary partial '
  'unique (company, branch, product) for Flutter upsert until Phase F.';

update public.inventory i
set is_default_variant = coalesce(v.is_default, false)
from public.product_variants v
where v.id = i.variant_id
  and i.is_default_variant is distinct from coalesce(v.is_default, false);

-- ---------------------------------------------------------------------------
-- Helper: resolve live default variant for a product in a company
-- ---------------------------------------------------------------------------

create or replace function public.resolve_default_product_variant(
  p_company_id uuid,
  p_product_id uuid
)
returns public.product_variants
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v public.product_variants%rowtype;
  cnt integer;
begin
  select count(*)::int into cnt
  from public.product_variants
  where company_id = p_company_id
    and product_id = p_product_id
    and is_default = true
    and deleted_at is null;

  if cnt = 0 then
    raise exception
      'No default variant for product % in company %.',
      p_product_id,
      p_company_id;
  end if;

  if cnt > 1 then
    raise exception
      'Multiple default variants for product % in company %.',
      p_product_id,
      p_company_id;
  end if;

  select * into v
  from public.product_variants
  where company_id = p_company_id
    and product_id = p_product_id
    and is_default = true
    and deleted_at is null;

  return v;
end;
$$;

revoke all on function public.resolve_default_product_variant(uuid, uuid) from public;
grant execute on function public.resolve_default_product_variant(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- New products: create default variant (Phase B shape)
-- ---------------------------------------------------------------------------

create or replace function public.ensure_default_variant_for_product()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.product_variants v
    where v.product_id = new.id
      and v.is_default = true
      and v.deleted_at is null
  ) then
    return new;
  end if;

  insert into public.product_variants (
    company_id,
    product_id,
    label,
    options,
    sku,
    barcode,
    selling_price,
    unit_cost,
    sort_order,
    is_default,
    is_active,
    deleted_at,
    created_by,
    updated_by
  )
  values (
    new.company_id,
    new.id,
    null,
    '{}'::jsonb,
    new.sku,
    new.barcode,
    coalesce(new.selling_price, 0),
    coalesce(new.unit_cost, 0),
    0,
    true,
    coalesce(new.is_active, true),
    new.deleted_at,
    new.created_by,
    new.updated_by
  );

  return new;
end;
$$;

drop trigger if exists trg_products_ensure_default_variant on public.products;
create trigger trg_products_ensure_default_variant
after insert on public.products
for each row execute function public.ensure_default_variant_for_product();

-- ---------------------------------------------------------------------------
-- inventory: fill variant_id + validate relationships
-- ---------------------------------------------------------------------------

create or replace function public.validate_inventory_tenant_scope()
returns trigger
language plpgsql
as $$
declare
  v public.product_variants%rowtype;
begin
  if not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'inventory.branch_id must belong to the same company';
  end if;

  -- Flutter may insert product_id without variant_id (pre-Phase F).
  if new.variant_id is null then
    if new.product_id is null then
      raise exception 'inventory requires product_id or variant_id';
    end if;
    v := public.resolve_default_product_variant(new.company_id, new.product_id);
    new.variant_id := v.id;
    new.product_id := v.product_id;
    new.is_default_variant := v.is_default;
  else
    select * into v
    from public.product_variants
    where id = new.variant_id;

    if not found then
      raise exception 'inventory.variant_id not found';
    end if;

    if v.company_id is distinct from new.company_id then
      raise exception 'inventory.variant_id must belong to the same company';
    end if;

    if new.product_id is null then
      new.product_id := v.product_id;
    elsif v.product_id is distinct from new.product_id then
      raise exception 'inventory.variant_id does not belong to inventory.product_id';
    end if;

    new.is_default_variant := coalesce(v.is_default, false);
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
  ) then
    raise exception 'inventory.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_inventory_validate_tenant_scope on public.inventory;
create trigger trg_inventory_validate_tenant_scope
before insert or update of company_id, branch_id, product_id, variant_id
on public.inventory
for each row execute function public.validate_inventory_tenant_scope();

-- ---------------------------------------------------------------------------
-- order_items: fill variant + historical snapshots for legacy inserts
-- ---------------------------------------------------------------------------

create or replace function public.fill_order_item_variant_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.product_variants%rowtype;
  pname text;
begin
  if new.variant_id is null then
    v := public.resolve_default_product_variant(new.company_id, new.product_id);
    new.variant_id := v.id;
  else
    select * into v
    from public.product_variants
    where id = new.variant_id;

    if not found then
      raise exception 'order_items.variant_id not found';
    end if;

    if v.company_id is distinct from new.company_id then
      raise exception 'order_items.variant_id must belong to the same company';
    end if;

    if v.product_id is distinct from new.product_id then
      raise exception 'order_items.variant_id does not belong to order_items.product_id';
    end if;
  end if;

  -- Snapshots only when missing (never rewrite historical values on update).
  if new.product_name is null or length(trim(new.product_name)) = 0 then
    select p.name into pname
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id;

    new.product_name := coalesce(nullif(trim(pname), ''), 'Product');
  end if;

  if new.sku is null or length(trim(new.sku)) = 0 then
    new.sku := v.sku;
  end if;

  if tg_op = 'INSERT' and new.variant_label is null then
    new.variant_label := nullif(trim(coalesce(v.label, '')), '');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_order_items_fill_variant_identity on public.order_items;
create trigger trg_order_items_fill_variant_identity
before insert or update of company_id, product_id, variant_id, product_name, sku, variant_label
on public.order_items
for each row execute function public.fill_order_item_variant_identity();

-- ---------------------------------------------------------------------------
-- stock_movements: validate variant matches product/company
-- ---------------------------------------------------------------------------

create or replace function public.validate_stock_movement_tenant_scope()
returns trigger
language plpgsql
as $$
declare
  v public.product_variants%rowtype;
begin
  if not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'stock_movements.branch_id must belong to the same company';
  end if;

  if new.variant_id is null then
    raise exception 'stock_movements.variant_id is required';
  end if;

  select * into v
  from public.product_variants
  where id = new.variant_id;

  if not found then
    raise exception 'stock_movements.variant_id not found';
  end if;

  if v.company_id is distinct from new.company_id then
    raise exception 'stock_movements.variant_id must belong to the same company';
  end if;

  if new.product_id is null then
    new.product_id := v.product_id;
  elsif v.product_id is distinct from new.product_id then
    raise exception
      'stock_movements.variant_id does not belong to stock_movements.product_id';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
  ) then
    raise exception 'stock_movements.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_stock_movements_validate_tenant_scope
  on public.stock_movements;
create trigger trg_stock_movements_validate_tenant_scope
before insert or update of company_id, branch_id, product_id, variant_id
on public.stock_movements
for each row execute function public.validate_stock_movement_tenant_scope();

-- ---------------------------------------------------------------------------
-- assert_order_line_stock_available — by variant_id
-- (same argument types; callers are server RPCs only)
-- Must DROP first: CREATE OR REPLACE cannot rename p_product_id → p_variant_id.
-- ---------------------------------------------------------------------------

drop function if exists public.assert_order_line_stock_available(
  uuid, uuid, uuid, numeric
);

create or replace function public.assert_order_line_stock_available(
  p_company_id uuid,
  p_branch_id uuid,
  p_variant_id uuid,
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
  display_name text;
  v public.product_variants%rowtype;
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

  select * into v
  from public.product_variants
  where id = p_variant_id
    and company_id = p_company_id;

  if not found then
    raise exception 'Variant not found for stock check.';
  end if;

  select
    coalesce(i.quantity, 0),
    coalesce(i.reserved_quantity, 0)
  into on_hand, reserved
  from public.inventory i
  where i.company_id = p_company_id
    and i.branch_id = p_branch_id
    and i.variant_id = p_variant_id;

  available := coalesce(on_hand, 0) - coalesce(reserved, 0);
  if available < 0 then
    available := 0;
  end if;

  if p_quantity > available then
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
end;
$$;

revoke all on function public.assert_order_line_stock_available(uuid, uuid, uuid, numeric)
  from public;
grant execute on function public.assert_order_line_stock_available(uuid, uuid, uuid, numeric)
  to authenticated;

-- ---------------------------------------------------------------------------
-- adjust_inventory — variant identity; product_id signature preserved
-- ---------------------------------------------------------------------------

drop function if exists public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid
);

create or replace function public.adjust_inventory(
  p_branch_id uuid,
  p_product_id uuid,
  p_quantity_delta numeric,
  p_movement_type text,
  p_reason text default null,
  p_notes text default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_variant_id uuid default null
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
  v public.product_variants%rowtype;
  new_qty numeric(14, 3);
  qty_before numeric(14, 3);
  movement_id uuid;
  product_name text;
  notify_label text;
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

  if p_variant_id is not null then
    select * into v
    from public.product_variants
    where id = p_variant_id
      and company_id = company
      and deleted_at is null;

    if not found then
      raise exception 'Variant not found.';
    end if;

    if p_product_id is not null and v.product_id is distinct from p_product_id then
      raise exception 'Variant does not belong to the supplied product.';
    end if;
  else
    if p_product_id is null then
      raise exception 'Product or variant is required.';
    end if;
    v := public.resolve_default_product_variant(company, p_product_id);
  end if;

  select coalesce(cs.allow_negative_stock, false)
    into allow_neg
  from public.company_settings cs
  where cs.company_id = company;

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
    company,
    p_branch_id,
    v.product_id,
    v.id,
    0,
    v.is_default,
    emp,
    emp
  )
  on conflict (company_id, branch_id, variant_id) do nothing;

  select * into inv
  from public.inventory
  where company_id = company
    and branch_id = p_branch_id
    and variant_id = v.id
  for update;

  if not found then
    raise exception 'Inventory row not found.';
  end if;

  if inv.product_id is distinct from v.product_id then
    raise exception 'Inventory product/variant mismatch.';
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
    variant_id,
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
    v.product_id,
    v.id,
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
    where p.id = v.product_id;

    notify_label := product_name;
    if v.label is not null and length(trim(v.label)) > 0 then
      notify_label := product_name || ' (' || trim(v.label) || ')';
    end if;

    perform public.emit_notifications_for_hub_roles(
      company,
      'inventory',
      'negative_stock',
      'Negative stock',
      notify_label || ' is now below zero stock.',
      'high',
      emp,
      'product',
      v.product_id,
      '/hub/inventory',
      jsonb_build_object(
        'branch_id', p_branch_id,
        'variant_id', v.id,
        'quantity_after', new_qty
      ),
      emp,
      'negative_stock:' || movement_id::text
    );
  end if;

  return inv;
end;
$$;

comment on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid, uuid
) is
  'Adjusts inventory by variant. Callers may omit p_variant_id to use the '
  'product default variant (Flutter compat until Phase F).';

revoke all on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid, uuid
) from public;
grant execute on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- place_sales_order — demand checks + insufficient-stock detect by variant
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
    if item.variant_id is null then
      raise exception 'Order line missing variant_id.';
    end if;

    perform public.assert_order_line_stock_available(
      company,
      o.branch_id,
      item.variant_id,
      item.quantity
    );
  end loop;

  for item in
    select * from public.order_items where order_id = o.id
  loop
    select i.quantity, coalesce(i.reserved_quantity, 0)
      into on_hand, reserved
    from public.inventory i
    where i.company_id = company
      and i.branch_id = o.branch_id
      and i.variant_id = item.variant_id;

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
  'Marks draft as placed. No inventory/payment. Stock guards use line variant_id.';

revoke all on function public.place_sales_order(uuid) from public;
grant execute on function public.place_sales_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- fulfill_order_items — deduct by order_items.variant_id
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
  'Delivers listed quantities, deducts variant inventory, recognizes AR, notifies on first partial.';

revoke all on function public.fulfill_order_items(uuid, jsonb) from public;
grant execute on function public.fulfill_order_items(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- complete_sales_order — fulfill remaining by variant_id
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
  'Fulfills remaining quantity by variant_id, recognizes unpaid delivered AR, marks completed.';

revoke all on function public.complete_sales_order(uuid) from public;
grant execute on function public.complete_sales_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Drop product-level unique ONLY after RPCs use variant ON CONFLICT
-- Replace with partial unique for Flutter default-variant upsert compat
-- ---------------------------------------------------------------------------

alter table public.inventory
  drop constraint if exists inventory_company_branch_product_key;

drop index if exists inventory_company_branch_product_compat_uidx;
create unique index inventory_company_branch_product_compat_uidx
  on public.inventory (company_id, branch_id, product_id)
  where is_default_variant;

comment on index public.inventory_company_branch_product_compat_uidx is
  'Phase E Flutter compat: upsert ON CONFLICT (company, branch, product) for '
  'default-variant rows only. Non-default variants are unconstrained at product grain. '
  'Remove in Phase F when app upserts by variant_id.';

-- Authoritative sellable uniqueness must remain.
do $verify_variant_unique$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.inventory'::regclass
      and conname = 'inventory_company_branch_variant_key'
  ) then
    raise exception
      'Phase E aborted: inventory_company_branch_variant_key missing after rewrite';
  end if;

  if exists (
    select 1
    from pg_constraint
    where conrelid = 'public.inventory'::regclass
      and conname = 'inventory_company_branch_product_key'
  ) then
    raise exception
      'Phase E aborted: product-level inventory unique still present';
  end if;
end;
$verify_variant_unique$;

-- allow_negative_stock cannot work while quantity >= 0 CHECK remains.
-- The setting has existed since migration 008; drop the blocking check so
-- allow_negative_stock=true can reduce quantity below zero as documented.
alter table public.inventory
  drop constraint if exists inventory_quantity_non_negative;
