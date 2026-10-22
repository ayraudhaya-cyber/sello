-- =============================================================================
-- 125 — Supplier orders
--
-- One order per supplier. Awaiting delivery does not move stock or what you
-- owe. Each receipt on that order adds the accepted quantity to the branch
-- and increases the supplier balance by accepted quantity × cost. A payment
-- reduces that balance. Cash and bank apply immediately. A cheque waits
-- until it is marked cleared.
-- =============================================================================

create table if not exists public.supplier_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  order_number text not null,
  supplier_name text not null,
  status text not null default 'draft',
  payment_method text,
  total numeric(14, 2) not null default 0,
  recognized_payable numeric(14, 2) not null default 0,
  notes text,
  ordered_at timestamptz,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint supplier_orders_number_not_blank
    check (length(trim(order_number)) > 0),
  constraint supplier_orders_supplier_name_not_blank
    check (length(trim(supplier_name)) > 0),
  constraint supplier_orders_status_allowed
    check (status in (
      'draft',
      'awaiting_delivery',
      'partially_received',
      'received',
      'cancelled'
    )),
  constraint supplier_orders_method_allowed
    check (payment_method is null or payment_method in ('cash', 'bank', 'cheque')),
  constraint supplier_orders_total_non_negative check (total >= 0),
  constraint supplier_orders_payable_non_negative check (recognized_payable >= 0)
);

create unique index if not exists supplier_orders_company_number_active_key
  on public.supplier_orders (company_id, order_number)
  where deleted_at is null;

create index if not exists supplier_orders_company_created_idx
  on public.supplier_orders (company_id, created_at desc)
  where deleted_at is null;

create index if not exists supplier_orders_supplier_idx
  on public.supplier_orders (supplier_id)
  where deleted_at is null;

create table if not exists public.supplier_order_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  order_id uuid not null references public.supplier_orders (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete restrict,
  variant_id uuid not null references public.product_variants (id) on delete restrict,
  product_name text not null,
  variant_label text,
  sku text,
  quantity numeric(14, 3) not null,
  received_quantity numeric(14, 3) not null default 0,
  cancelled_quantity numeric(14, 3) not null default 0,
  unit_cost numeric(14, 2) not null default 0,
  line_total numeric(14, 2) not null default 0,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint supplier_order_lines_qty_positive check (quantity > 0),
  constraint supplier_order_lines_received_non_negative check (received_quantity >= 0),
  constraint supplier_order_lines_cancelled_non_negative check (cancelled_quantity >= 0),
  constraint supplier_order_lines_cost_non_negative check (unit_cost >= 0),
  constraint supplier_order_lines_total_non_negative check (line_total >= 0),
  constraint supplier_order_lines_name_not_blank
    check (length(trim(product_name)) > 0)
);

create unique index if not exists supplier_order_lines_order_variant_key
  on public.supplier_order_lines (order_id, variant_id);

create index if not exists supplier_order_lines_order_idx
  on public.supplier_order_lines (order_id);

create table if not exists public.supplier_receipts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  order_id uuid not null references public.supplier_orders (id) on delete restrict,
  receipt_number text not null,
  received_at timestamptz not null default timezone('utc', now()),
  created_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),

  constraint supplier_receipts_number_not_blank
    check (length(trim(receipt_number)) > 0)
);

create unique index if not exists supplier_receipts_company_number_key
  on public.supplier_receipts (company_id, receipt_number);

create index if not exists supplier_receipts_order_idx
  on public.supplier_receipts (order_id);

create table if not exists public.supplier_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  receipt_id uuid not null references public.supplier_receipts (id) on delete cascade,
  order_line_id uuid not null references public.supplier_order_lines (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  variant_id uuid not null references public.product_variants (id) on delete restrict,
  quantity numeric(14, 3) not null,
  unit_cost numeric(14, 2) not null default 0,
  line_value numeric(14, 2) not null default 0,
  created_at timestamptz not null default timezone('utc', now()),

  constraint supplier_receipt_lines_qty_positive check (quantity > 0),
  constraint supplier_receipt_lines_cost_non_negative check (unit_cost >= 0)
);

create index if not exists supplier_receipt_lines_receipt_idx
  on public.supplier_receipt_lines (receipt_id);

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  order_id uuid not null references public.supplier_orders (id) on delete restrict,
  payment_number text not null,
  amount numeric(14, 2) not null,
  method text not null,
  status text not null default 'completed',
  reference text,
  notes text,
  paid_at timestamptz not null default timezone('utc', now()),
  cleared_at timestamptz,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint supplier_payments_number_not_blank
    check (length(trim(payment_number)) > 0),
  constraint supplier_payments_amount_positive check (amount > 0),
  constraint supplier_payments_method_allowed
    check (method in ('cash', 'bank', 'cheque')),
  constraint supplier_payments_status_allowed
    check (status in ('completed', 'pending', 'cancelled'))
);

create unique index if not exists supplier_payments_company_number_active_key
  on public.supplier_payments (company_id, payment_number)
  where deleted_at is null;

create index if not exists supplier_payments_order_idx
  on public.supplier_payments (order_id)
  where deleted_at is null;

alter table public.supplier_orders enable row level security;
alter table public.supplier_order_lines enable row level security;
alter table public.supplier_receipts enable row level security;
alter table public.supplier_receipt_lines enable row level security;
alter table public.supplier_payments enable row level security;

drop policy if exists "supplier_orders_select_own_company" on public.supplier_orders;
create policy "supplier_orders_select_own_company"
  on public.supplier_orders for select to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

drop policy if exists "supplier_order_lines_select_own_company" on public.supplier_order_lines;
create policy "supplier_order_lines_select_own_company"
  on public.supplier_order_lines for select to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "supplier_receipts_select_own_company" on public.supplier_receipts;
create policy "supplier_receipts_select_own_company"
  on public.supplier_receipts for select to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "supplier_receipt_lines_select_own_company" on public.supplier_receipt_lines;
create policy "supplier_receipt_lines_select_own_company"
  on public.supplier_receipt_lines for select to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "supplier_payments_select_own_company" on public.supplier_payments;
create policy "supplier_payments_select_own_company"
  on public.supplier_payments for select to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

comment on table public.supplier_orders is
  'An order placed with a supplier. Stock and the amount owed move when goods are received.';

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

create or replace function public.refresh_supplier_order_status(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_status text;
  any_received boolean;
  any_open boolean;
begin
  select status into current_status
  from public.supplier_orders
  where id = p_order_id
    and deleted_at is null;

  if current_status is null or current_status in ('draft', 'cancelled') then
    return;
  end if;

  select coalesce(bool_or(received_quantity > 0.0001), false)
    into any_received
  from public.supplier_order_lines
  where order_id = p_order_id;

  select coalesce(bool_or(received_quantity + cancelled_quantity + 0.0001 < quantity), false)
    into any_open
  from public.supplier_order_lines
  where order_id = p_order_id;

  update public.supplier_orders
  set
    status = case
      when any_received and any_open then 'partially_received'
      when any_received then 'received'
      else 'awaiting_delivery'
    end,
    updated_at = timezone('utc', now())
  where id = p_order_id;
end;
$$;

revoke all on function public.refresh_supplier_order_status(uuid) from public;
grant execute on function public.refresh_supplier_order_status(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Save / place
-- ---------------------------------------------------------------------------

create or replace function public.save_supplier_order(
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
  existing public.supplier_orders%rowtype;
  supplier public.suppliers%rowtype;
  v_branch_id uuid;
  v_method text;
  v_notes text;
  place_now boolean;
  line jsonb;
  variant public.product_variants%rowtype;
  product_name text;
  variant_label text;
  qty numeric(14, 3);
  cost numeric(14, 2);
  line_total numeric(14, 2);
  order_total numeric(14, 2) := 0;
  order_no text;
  seq bigint;
  stamp text;
  received numeric(14, 3);
  seen uuid[] := '{}';
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'This supplier order is missing its details.';
  end if;

  if jsonb_typeof(p_payload -> 'lines') <> 'array'
     or jsonb_array_length(p_payload -> 'lines') = 0 then
    raise exception 'Add at least one product.';
  end if;

  select * into supplier
  from public.suppliers
  where id = nullif(p_payload ->> 'supplier_id', '')::uuid
    and company_id = company
    and deleted_at is null;

  if not found or supplier.is_active is not true then
    raise exception 'Choose an active supplier.';
  end if;

  v_branch_id := nullif(p_payload ->> 'branch_id', '')::uuid;
  if v_branch_id is null or not exists (
    select 1 from public.branches b
    where b.id = v_branch_id
      and b.company_id = company
      and b.deleted_at is null
      and b.is_active = true
  ) then
    raise exception 'Choose a branch.';
  end if;

  v_method := nullif(trim(p_payload ->> 'payment_method'), '');
  if v_method is not null and v_method not in ('cash', 'bank', 'cheque') then
    raise exception 'Choose cash, bank, or cheque.';
  end if;

  v_notes := nullif(trim(p_payload ->> 'notes'), '');
  place_now := coalesce((p_payload ->> 'place')::boolean, false);

  if p_order_id is not null then
    select * into existing
    from public.supplier_orders
    where id = p_order_id
      and company_id = company
      and deleted_at is null
    for update;

    if not found then
      raise exception 'Supplier order not found.';
    end if;

    if existing.status not in ('draft', 'awaiting_delivery') then
      raise exception 'This order can no longer be changed.';
    end if;

    select coalesce(sum(received_quantity), 0) into received
    from public.supplier_order_lines
    where order_id = existing.id;

    if received > 0.0001 then
      raise exception 'Goods have already been received, so the lines stay as they are.';
    end if;
  end if;

  -- Measure lines before writing.
  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    qty := (line ->> 'quantity')::numeric;
    cost := coalesce((line ->> 'unit_cost')::numeric, 0);
    if qty is null or qty <= 0 then
      raise exception 'Each product needs a quantity greater than zero.';
    end if;
    if cost < 0 then
      raise exception 'Cost cannot be negative.';
    end if;
    order_total := order_total + round(qty * cost, 2);
  end loop;

  if p_order_id is null then
    stamp := to_char(timezone('Asia/Colombo', now()), 'YYYYMMDD');
    select count(*) + 1 into seq
    from public.supplier_orders o
    where o.company_id = company
      and timezone('Asia/Colombo', o.created_at)::date
          = timezone('Asia/Colombo', now())::date;

    order_no := 'PO-' || stamp || '-' || lpad(seq::text, 4, '0');

    insert into public.supplier_orders (
      company_id, branch_id, supplier_id, order_number, supplier_name,
      status, payment_method, total, notes, ordered_at, created_by, updated_by
    )
    values (
      company,
      v_branch_id,
      supplier.id,
      order_no,
      supplier.name,
      case when place_now then 'awaiting_delivery' else 'draft' end,
      v_method,
      order_total,
      v_notes,
      case when place_now then timezone('utc', now()) else null end,
      emp,
      emp
    )
    returning * into existing;
  else
    update public.supplier_orders
    set
      branch_id = v_branch_id,
      supplier_id = supplier.id,
      supplier_name = supplier.name,
      status = case
        when place_now then 'awaiting_delivery'
        else supplier_orders.status
      end,
      payment_method = v_method,
      total = order_total,
      notes = v_notes,
      ordered_at = case
        when place_now and ordered_at is null then timezone('utc', now())
        else ordered_at
      end,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = existing.id
    returning * into existing;

    delete from public.supplier_order_lines where order_id = existing.id;
  end if;

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    qty := (line ->> 'quantity')::numeric;
    cost := round(coalesce((line ->> 'unit_cost')::numeric, 0), 2);
    line_total := round(qty * cost, 2);

    if nullif(line ->> 'variant_id', '') is null then
      variant := public.resolve_default_product_variant(
        company,
        (line ->> 'product_id')::uuid
      );
    else
      select * into variant
      from public.product_variants v
      where v.id = (line ->> 'variant_id')::uuid
        and v.company_id = company
        and v.product_id = (line ->> 'product_id')::uuid
        and v.deleted_at is null;
      if not found then
        raise exception 'A product on this order is no longer available.';
      end if;
    end if;

    if variant.id = any (seen) then
      raise exception 'Each product can appear once on the order.';
    end if;
    seen := array_append(seen, variant.id);

    select p.name into product_name
    from public.products p
    where p.id = variant.product_id
      and p.company_id = company
      and p.deleted_at is null;

    if product_name is null then
      raise exception 'A product on this order is no longer available.';
    end if;

    variant_label := nullif(trim(coalesce(variant.label, '')), '');
    if variant_label is not null and lower(variant_label) = 'default' then
      variant_label := null;
    end if;

    insert into public.supplier_order_lines (
      company_id, order_id, product_id, variant_id,
      product_name, variant_label, sku,
      quantity, unit_cost, line_total, created_by, updated_by
    )
    values (
      company, existing.id, variant.product_id, variant.id,
      product_name, variant_label, variant.sku,
      qty, cost, line_total, emp, emp
    );
  end loop;

  return jsonb_build_object(
    'id', existing.id,
    'order_number', existing.order_number,
    'status', existing.status
  );
end;
$$;

revoke all on function public.save_supplier_order(uuid, jsonb) from public;
grant execute on function public.save_supplier_order(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Receive
-- ---------------------------------------------------------------------------

create or replace function public.receive_supplier_order(
  p_order_id uuid,
  p_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  o public.supplier_orders%rowtype;
  item public.supplier_order_lines%rowtype;
  line jsonb;
  qty numeric(14, 3);
  line_value numeric(14, 2);
  receipt_total numeric(14, 2) := 0;
  receipt_id uuid;
  receipt_no text;
  seq bigint;
  stamp text;
  line_count integer := 0;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_lines is null
     or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception 'Enter at least one quantity to receive.';
  end if;

  select * into o
  from public.supplier_orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Supplier order not found.';
  end if;

  if o.status not in ('awaiting_delivery', 'partially_received') then
    raise exception 'Place the order before receiving goods.';
  end if;

  for line in select value from jsonb_array_elements(p_lines)
  loop
    qty := coalesce((line ->> 'quantity')::numeric, 0);
    if qty <= 0 then
      continue;
    end if;
    line_count := line_count + 1;

    select * into item
    from public.supplier_order_lines
    where id = (line ->> 'order_line_id')::uuid
      and order_id = o.id
    for update;

    if not found then
      raise exception 'A product line on this order could not be found.';
    end if;

    receipt_total := receipt_total + round(qty * item.unit_cost, 2);
  end loop;

  if line_count = 0 then
    raise exception 'Enter at least one quantity to receive.';
  end if;

  stamp := to_char(timezone('Asia/Colombo', now()), 'YYYYMMDD');
  select count(*) + 1 into seq
  from public.supplier_receipts r
  where r.company_id = company
    and timezone('Asia/Colombo', r.received_at)::date
        = timezone('Asia/Colombo', now())::date;

  receipt_no := 'GRN-' || stamp || '-' || lpad(seq::text, 4, '0');

  insert into public.supplier_receipts (
    company_id, branch_id, supplier_id, order_id, receipt_number, created_by
  )
  values (
    company, o.branch_id, o.supplier_id, o.id, receipt_no, emp
  )
  returning id into receipt_id;

  for line in select value from jsonb_array_elements(p_lines)
  loop
    qty := coalesce((line ->> 'quantity')::numeric, 0);
    if qty <= 0 then
      continue;
    end if;

    select * into item
    from public.supplier_order_lines
    where id = (line ->> 'order_line_id')::uuid
      and order_id = o.id
    for update;

    line_value := round(qty * item.unit_cost, 2);

    insert into public.supplier_receipt_lines (
      company_id, receipt_id, order_line_id, product_id, variant_id,
      quantity, unit_cost, line_value
    )
    values (
      company, receipt_id, item.id, item.product_id, item.variant_id,
      qty, item.unit_cost, line_value
    );

    update public.supplier_order_lines
    set
      received_quantity = received_quantity + qty,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = item.id;

    perform public.adjust_inventory(
      o.branch_id,
      item.product_id,
      qty,
      'purchase',
      'Supplier receipt ' || receipt_no,
      o.order_number,
      'supplier_receipt',
      receipt_id,
      item.variant_id
    );
  end loop;

  update public.supplier_orders
  set
    recognized_payable = recognized_payable + receipt_total,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  update public.suppliers
  set
    current_balance = current_balance + receipt_total,
    last_purchase_at = timezone('utc', now()),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.supplier_id
    and company_id = company
    and deleted_at is null;

  perform public.refresh_supplier_order_status(o.id);

  return jsonb_build_object(
    'id', receipt_id,
    'receipt_number', receipt_no,
    'value', receipt_total
  );
end;
$$;

revoke all on function public.receive_supplier_order(uuid, jsonb) from public;
grant execute on function public.receive_supplier_order(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Close what will not arrive / cancel before any receipt
-- ---------------------------------------------------------------------------

create or replace function public.close_supplier_order_remaining(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  o public.supplier_orders%rowtype;
  received numeric(14, 3);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into o
  from public.supplier_orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Supplier order not found.';
  end if;

  if o.status not in ('awaiting_delivery', 'partially_received') then
    raise exception 'There is nothing left to close on this order.';
  end if;

  select coalesce(sum(received_quantity), 0) into received
  from public.supplier_order_lines
  where order_id = o.id;

  if received <= 0.0001 then
    update public.supplier_orders
    set
      status = 'cancelled',
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;
    return;
  end if;

  update public.supplier_order_lines
  set
    cancelled_quantity = greatest(quantity - received_quantity, 0),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where order_id = o.id;

  perform public.refresh_supplier_order_status(o.id);
end;
$$;

revoke all on function public.close_supplier_order_remaining(uuid) from public;
grant execute on function public.close_supplier_order_remaining(uuid) to authenticated;

create or replace function public.cancel_supplier_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  o public.supplier_orders%rowtype;
  received numeric(14, 3);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into o
  from public.supplier_orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Supplier order not found.';
  end if;

  if o.status not in ('draft', 'awaiting_delivery') then
    raise exception 'This order can no longer be cancelled.';
  end if;

  select coalesce(sum(received_quantity), 0) into received
  from public.supplier_order_lines
  where order_id = o.id;

  if received > 0.0001 then
    raise exception 'Goods have already been received. Close only what will not arrive.';
  end if;

  update public.supplier_orders
  set
    status = 'cancelled',
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;
end;
$$;

revoke all on function public.cancel_supplier_order(uuid) from public;
grant execute on function public.cancel_supplier_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Payments
-- ---------------------------------------------------------------------------

create or replace function public.record_supplier_payment(
  p_order_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  o public.supplier_orders%rowtype;
  method text := lower(trim(coalesce(p_method, '')));
  amount numeric(14, 2);
  status text;
  payment_id uuid;
  payment_no text;
  seq bigint;
  stamp text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  amount := round(coalesce(p_amount, 0), 2);
  if amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;

  if method not in ('cash', 'bank', 'cheque') then
    raise exception 'Choose cash, bank, or cheque.';
  end if;

  select * into o
  from public.supplier_orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Supplier order not found.';
  end if;

  if o.status = 'draft' then
    raise exception 'Place the order before recording a payment.';
  end if;

  if o.status = 'cancelled' then
    raise exception 'This order is cancelled.';
  end if;

  status := case when method = 'cheque' then 'pending' else 'completed' end;

  stamp := to_char(timezone('Asia/Colombo', now()), 'YYYYMMDD');
  select count(*) + 1 into seq
  from public.supplier_payments p
  where p.company_id = company
    and timezone('Asia/Colombo', p.created_at)::date
        = timezone('Asia/Colombo', now())::date;

  payment_no := 'SP-' || stamp || '-' || lpad(seq::text, 4, '0');

  insert into public.supplier_payments (
    company_id, branch_id, supplier_id, order_id,
    payment_number, amount, method, status, reference, notes,
    cleared_at, created_by, updated_by
  )
  values (
    company, o.branch_id, o.supplier_id, o.id,
    payment_no, amount, method, status,
    nullif(trim(coalesce(p_reference, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    case when status = 'completed' then timezone('utc', now()) else null end,
    emp, emp
  )
  returning id into payment_id;

  if status = 'completed' then
    update public.suppliers
    set
      current_balance = current_balance - amount,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.supplier_id
      and company_id = company
      and deleted_at is null;
  end if;

  return jsonb_build_object(
    'id', payment_id,
    'payment_number', payment_no,
    'status', status
  );
end;
$$;

revoke all on function public.record_supplier_payment(uuid, numeric, text, text, text) from public;
grant execute on function public.record_supplier_payment(uuid, numeric, text, text, text) to authenticated;

create or replace function public.clear_supplier_cheque(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  p public.supplier_payments%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into p
  from public.supplier_payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if p.method <> 'cheque' or p.status <> 'pending' then
    raise exception 'This payment is not a cheque waiting to clear.';
  end if;

  update public.supplier_payments
  set
    status = 'completed',
    cleared_at = timezone('utc', now()),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p.id;

  update public.suppliers
  set
    current_balance = current_balance - p.amount,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p.supplier_id
    and company_id = company
    and deleted_at is null;
end;
$$;

revoke all on function public.clear_supplier_cheque(uuid) from public;
grant execute on function public.clear_supplier_cheque(uuid) to authenticated;
