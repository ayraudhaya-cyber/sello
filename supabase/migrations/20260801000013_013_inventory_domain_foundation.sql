-- =============================================================================
-- Migration 013 — Inventory domain foundation
--
-- Append-only stock_movements ledger, adjust_inventory RPC, and sale movements
-- recorded from complete_sales_order. Multi-location / batch / expiry reserved
-- via nullable columns for future use.
-- =============================================================================

-- Track last movement for Hub list without joining the ledger every time.
alter table public.inventory
  add column if not exists last_movement_at timestamptz;

comment on column public.inventory.last_movement_at is
  'Timestamp of the most recent stock_movements row for this inventory record.';

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  movement_type text not null,
  quantity_delta numeric(14, 3) not null,
  quantity_after numeric(14, 3) not null,
  reason text,
  notes text,
  reference_type text,
  reference_id uuid,
  -- Future: warehouse / multi-location / batch / expiry
  from_branch_id uuid references public.branches (id) on delete set null,
  to_branch_id uuid references public.branches (id) on delete set null,
  batch_code text,
  expires_at date,
  created_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),

  constraint stock_movements_type_allowed check (
    movement_type in (
      'purchase',
      'sale',
      'damage',
      'return',
      'correction',
      'transfer',
      'adjustment'
    )
  ),
  constraint stock_movements_delta_nonzero check (quantity_delta <> 0),
  constraint stock_movements_quantity_after_finite
    check (quantity_after = quantity_after),
  constraint stock_movements_notes_not_blank
    check (notes is null or length(trim(notes)) > 0),
  constraint stock_movements_reason_not_blank
    check (reason is null or length(trim(reason)) > 0),
  constraint stock_movements_batch_not_blank
    check (batch_code is null or length(trim(batch_code)) > 0)
);

create index if not exists stock_movements_company_created_at_idx
  on public.stock_movements (company_id, created_at desc);

create index if not exists stock_movements_product_created_at_idx
  on public.stock_movements (company_id, product_id, created_at desc);

create index if not exists stock_movements_branch_product_idx
  on public.stock_movements (company_id, branch_id, product_id, created_at desc);

create index if not exists stock_movements_reference_idx
  on public.stock_movements (reference_type, reference_id)
  where reference_id is not null;

comment on table public.stock_movements is
  'Append-only inventory ledger. Current stock lives on inventory.quantity.';
comment on column public.stock_movements.movement_type is
  'purchase | sale | damage | return | correction | transfer | adjustment';
comment on column public.stock_movements.from_branch_id is
  'Reserved for multi-location transfers.';
comment on column public.stock_movements.batch_code is
  'Reserved for batch / lot tracking.';
comment on column public.stock_movements.expires_at is
  'Reserved for expiry-dated inventory.';

create or replace function public.validate_stock_movement_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'stock_movements.branch_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
      and p.deleted_at is null
  ) then
    raise exception 'stock_movements.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_stock_movements_validate_tenant_scope
  on public.stock_movements;
create trigger trg_stock_movements_validate_tenant_scope
before insert or update of company_id, branch_id, product_id
on public.stock_movements
for each row execute function public.validate_stock_movement_tenant_scope();

-- ---------------------------------------------------------------------------
-- adjust_inventory
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
  );

  return inv;
end;
$$;

revoke all on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid
) from public;
grant execute on function public.adjust_inventory(
  uuid, uuid, numeric, text, text, text, text, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- complete_sales_order — use adjust_inventory so sales enter the ledger
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

  if o.status not in ('draft', 'submitted') then
    raise exception 'Only draft orders can be completed.';
  end if;

  if not exists (
    select 1 from public.order_items oi where oi.order_id = o.id
  ) then
    raise exception 'Add at least one product before completing the order.';
  end if;

  for item in
    select * from public.order_items where order_id = o.id
  loop
    perform public.adjust_inventory(
      o.branch_id,
      item.product_id,
      -item.quantity,
      'sale',
      'Sold',
      null,
      'order',
      o.id
    );
  end loop;

  if coalesce(o.payment_method, '') in ('cash', 'card', 'bank_transfer', 'wallet') then
    update public.orders
    set
      status = 'completed',
      payment_status = 'paid',
      completed_at = timezone('utc', now()),
      updated_by = emp
    where id = o.id;

    update public.customers
    set
      last_purchase_at = greatest(
        coalesce(last_purchase_at, o.ordered_at),
        coalesce(o.ordered_at, timezone('utc', now()))
      ),
      updated_by = emp
    where id = o.customer_id
      and deleted_at is null;
  else
    update public.orders
    set
      status = 'completed',
      payment_status = 'unpaid',
      completed_at = timezone('utc', now()),
      updated_by = emp
    where id = o.id;

    update public.customers
    set
      current_balance = current_balance + o.total,
      last_purchase_at = greatest(
        coalesce(last_purchase_at, o.ordered_at),
        coalesce(o.ordered_at, timezone('utc', now()))
      ),
      updated_by = emp
    where id = o.customer_id
      and deleted_at is null;
  end if;
end;
$$;

revoke all on function public.complete_sales_order(uuid) from public;
grant execute on function public.complete_sales_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.stock_movements enable row level security;

drop policy if exists "stock_movements_select_own_company" on public.stock_movements;
create policy "stock_movements_select_own_company"
  on public.stock_movements
  for select
  to authenticated
  using (company_id = public.current_company_id());

-- Inserts happen via security definer RPCs; allow direct insert for tooling.
drop policy if exists "stock_movements_insert_own_company" on public.stock_movements;
create policy "stock_movements_insert_own_company"
  on public.stock_movements
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
  );
