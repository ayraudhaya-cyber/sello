-- =============================================================================
-- 126 — Client operation receipts
--
-- A retry that sends the same company, operation id, operation name, and
-- payload gets the original result and does not repeat the effect.
-- A missing operation id is not idempotent: those calls behave as before.
--
-- The receipt row, the business writes, and the stored result commit or
-- roll back together. Helpers are not granted to API roles.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.client_operation_receipts (
  company_id uuid not null references public.companies (id) on delete restrict,
  operation_id uuid not null,
  operation_name text not null,
  payload_hash text not null,
  result jsonb,
  created_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (company_id, operation_id),
  constraint client_operation_receipts_name_not_blank
    check (length(trim(operation_name)) > 0),
  constraint client_operation_receipts_hash_sha256
    check (payload_hash ~ '^[0-9a-f]{64}$')
);

comment on table public.client_operation_receipts is
  'One row per company and client operation id. result is null only until the claiming transaction stores it; a committed row always has the original result.';

comment on column public.client_operation_receipts.payload_hash is
  'SHA-256 hex of the canonical jsonb request. A different hash or operation name for the same id is rejected.';

alter table public.client_operation_receipts enable row level security;

revoke all on table public.client_operation_receipts
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Helpers. Security definer RPCs call these as the function owner.
-- ---------------------------------------------------------------------------

create or replace function public.client_operation_payload_hash(p_payload jsonb)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select encode(
    extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256'),
    'hex'
  );
$$;

create or replace function public.begin_client_operation(
  p_operation_id uuid,
  p_operation_name text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
  emp uuid := public.current_employee_id();
  v_name text := nullif(trim(coalesce(p_operation_name, '')), '');
  v_hash text;
  inserted uuid;
  existing public.client_operation_receipts%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_operation_id is null then
    raise exception 'Operation id is required.';
  end if;

  if v_name is null then
    raise exception 'Operation name is required.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Operation payload is required.';
  end if;

  v_hash := public.client_operation_payload_hash(p_payload);
  inserted := null;

  -- The unique index makes the loser wait until the winner commits or rolls back.
  insert into public.client_operation_receipts (
    company_id,
    operation_id,
    operation_name,
    payload_hash,
    created_by
  )
  values (company, p_operation_id, v_name, v_hash, emp)
  on conflict (company_id, operation_id) do nothing
  returning operation_id into inserted;

  if inserted is not null then
    return null;
  end if;

  select * into existing
  from public.client_operation_receipts
  where company_id = company
    and operation_id = p_operation_id
  for update;

  if not found then
    inserted := null;
    insert into public.client_operation_receipts (
      company_id,
      operation_id,
      operation_name,
      payload_hash,
      created_by
    )
    values (company, p_operation_id, v_name, v_hash, emp)
    on conflict (company_id, operation_id) do nothing
    returning operation_id into inserted;

    if inserted is not null then
      return null;
    end if;

    select * into existing
    from public.client_operation_receipts
    where company_id = company
      and operation_id = p_operation_id
    for update;

    if not found then
      raise exception 'This operation id could not be claimed.';
    end if;
  end if;

  if existing.operation_name is distinct from v_name
     or existing.payload_hash is distinct from v_hash then
    raise exception 'This operation id was already used for a different request.';
  end if;

  if existing.result is null then
    raise exception 'This operation id is already in progress.';
  end if;

  return existing.result;
end;
$$;

create or replace function public.finish_client_operation(
  p_operation_id uuid,
  p_result jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
  emp uuid := public.current_employee_id();
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_operation_id is null then
    raise exception 'Operation id is required.';
  end if;

  if p_result is null or jsonb_typeof(p_result) <> 'object' then
    raise exception 'Operation result is required.';
  end if;

  update public.client_operation_receipts
  set result = p_result
  where company_id = company
    and operation_id = p_operation_id
    and result is null;

  if not found then
    raise exception 'Operation receipt could not be completed.';
  end if;
end;
$$;

revoke all on function public.client_operation_payload_hash(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.begin_client_operation(uuid, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.finish_client_operation(uuid, jsonb)
  from public, anon, authenticated, service_role;

comment on function public.begin_client_operation(uuid, text, jsonb) is
  'Claims a receipt or returns the original result. Null means the caller must perform the effect and then finish_client_operation.';

-- ---------------------------------------------------------------------------
-- adjust_inventory — same rules, optional trailing operation id
-- ---------------------------------------------------------------------------

drop function if exists public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid, uuid
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
  p_variant_id uuid default null,
  p_operation_id uuid default null
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
  replay jsonb;
  op_payload jsonb;
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

  if p_operation_id is not null then
    op_payload := jsonb_build_object(
      'branch_id', p_branch_id,
      'product_id', p_product_id,
      'variant_id', p_variant_id,
      'quantity_delta', to_jsonb(p_quantity_delta),
      'movement_type', p_movement_type,
      'reason', nullif(trim(coalesce(p_reason, '')), ''),
      'notes', nullif(trim(coalesce(p_notes, '')), ''),
      'reference_type', nullif(trim(coalesce(p_reference_type, '')), ''),
      'reference_id', p_reference_id
    );
    replay := public.begin_client_operation(
      p_operation_id,
      'adjust_inventory',
      op_payload
    );
    if replay is not null then
      return jsonb_populate_record(null::public.inventory, replay);
    end if;
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

  if p_operation_id is not null then
    perform public.finish_client_operation(p_operation_id, to_jsonb(inv));
  end if;

  return inv;
end;
$$;

comment on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid, uuid, uuid
) is
  'Adjusts inventory by variant. Callers may omit p_variant_id to use the product default variant. p_operation_id is optional; omitted calls are not idempotent.';

revoke all on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid, uuid, uuid
) from public;
grant execute on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid, uuid, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- receive_payment — same settlement rules, optional trailing operation id
-- ---------------------------------------------------------------------------

drop function if exists public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric
);

create or replace function public.receive_payment(
  p_customer_id uuid,
  p_amount numeric,
  p_method text,
  p_allocations jsonb default '[]'::jsonb,
  p_reference text default null,
  p_notes text default null,
  p_visit_id uuid default null,
  p_discount_amount numeric default 0,
  p_operation_id uuid default null
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
  replay jsonb;
  op_payload jsonb;
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

  if p_operation_id is not null then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'order_id', nullif(trim(coalesce(elem->>'order_id', '')), ''),
          'receivable_adjustment_id', nullif(trim(coalesce(elem->>'receivable_adjustment_id', '')), ''),
          'amount', to_jsonb((elem->>'amount')::numeric)
        )
        order by
          nullif(trim(coalesce(elem->>'order_id', '')), ''),
          nullif(trim(coalesce(elem->>'receivable_adjustment_id', '')), ''),
          (elem->>'amount')::numeric
      ),
      '[]'::jsonb
    )
      into op_payload
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) elem;

    op_payload := jsonb_build_object(
      'customer_id', p_customer_id,
      'amount', to_jsonb(cash_amount),
      'discount_amount', to_jsonb(discount_amount),
      'method', method_code,
      'reference', nullif(trim(coalesce(p_reference, '')), ''),
      'notes', nullif(trim(coalesce(p_notes, '')), ''),
      'visit_id', p_visit_id,
      'allocations', op_payload
    );
    replay := public.begin_client_operation(
      p_operation_id,
      'receive_payment',
      op_payload
    );
    if replay is not null then
      return (replay->>'payment_id')::uuid;
    end if;
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

  if p_operation_id is not null then
    perform public.finish_client_operation(
      p_operation_id,
      jsonb_build_object('payment_id', payment_id)
    );
  end if;

  return payment_id;
end;
$$;

comment on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric, uuid
) is
  'Records a collection. Cash may be zero when discount alone settles allocated receivables. p_operation_id is optional; omitted calls are not idempotent.';

revoke all on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric, uuid
) from public;
grant execute on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid, numeric, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- receive_supplier_order — same receipt rules, optional operation id
-- Inner adjust_inventory calls stay non-idempotent; the receipt covers the
-- whole goods receipt.
-- ---------------------------------------------------------------------------

drop function if exists public.receive_supplier_order(uuid, jsonb);

create or replace function public.receive_supplier_order(
  p_order_id uuid,
  p_lines jsonb,
  p_operation_id uuid default null
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
  replay jsonb;
  op_lines jsonb;
  op_result jsonb;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_lines is null
     or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception 'Enter at least one quantity to receive.';
  end if;

  if p_operation_id is not null then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'order_line_id', elem->>'order_line_id',
          'quantity', to_jsonb(coalesce((elem->>'quantity')::numeric, 0))
        )
        order by elem->>'order_line_id'
      ),
      '[]'::jsonb
    )
      into op_lines
    from jsonb_array_elements(p_lines) elem
    where coalesce((elem->>'quantity')::numeric, 0) > 0;

    replay := public.begin_client_operation(
      p_operation_id,
      'receive_supplier_order',
      jsonb_build_object('order_id', p_order_id, 'lines', op_lines)
    );
    if replay is not null then
      return replay;
    end if;
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

  op_result := jsonb_build_object(
    'id', receipt_id,
    'receipt_number', receipt_no,
    'value', receipt_total
  );

  if p_operation_id is not null then
    perform public.finish_client_operation(p_operation_id, op_result);
  end if;

  return op_result;
end;
$$;

comment on function public.receive_supplier_order(uuid, jsonb, uuid) is
  'Receives goods on a supplier order. p_operation_id is optional; omitted calls are not idempotent.';

revoke all on function public.receive_supplier_order(uuid, jsonb, uuid) from public;
grant execute on function public.receive_supplier_order(uuid, jsonb, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- record_supplier_payment — same balance rules, optional operation id
-- ---------------------------------------------------------------------------

drop function if exists public.record_supplier_payment(
  uuid, numeric, text, text, text
);

create or replace function public.record_supplier_payment(
  p_order_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text default null,
  p_notes text default null,
  p_operation_id uuid default null
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
  replay jsonb;
  op_result jsonb;
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

  if p_operation_id is not null then
    replay := public.begin_client_operation(
      p_operation_id,
      'record_supplier_payment',
      jsonb_build_object(
        'order_id', p_order_id,
        'amount', to_jsonb(amount),
        'method', method,
        'reference', nullif(trim(coalesce(p_reference, '')), ''),
        'notes', nullif(trim(coalesce(p_notes, '')), '')
      )
    );
    if replay is not null then
      return replay;
    end if;
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

  op_result := jsonb_build_object(
    'id', payment_id,
    'payment_number', payment_no,
    'status', status
  );

  if p_operation_id is not null then
    perform public.finish_client_operation(p_operation_id, op_result);
  end if;

  return op_result;
end;
$$;

comment on function public.record_supplier_payment(
  uuid, numeric, text, text, text, uuid
) is
  'Records a supplier payment. Cash and bank reduce the balance immediately. A cheque stays pending. p_operation_id is optional; omitted calls are not idempotent.';

revoke all on function public.record_supplier_payment(
  uuid, numeric, text, text, text, uuid
) from public;
grant execute on function public.record_supplier_payment(
  uuid, numeric, text, text, text, uuid
) to authenticated;
