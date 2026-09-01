  -- =============================================================================
  -- Migration 011 — Orders domain foundation
  --
  -- RLS for orders / order_items, payment foundation columns, order-number
  -- allocator, and complete_sales_order (stock + customer purchase side-effects).
  -- =============================================================================

  -- ---------------------------------------------------------------------------
  -- Columns (payment + totals extensibility)
  -- ---------------------------------------------------------------------------

  alter table public.orders
    add column if not exists payment_status text not null default 'unpaid';

  alter table public.orders
    add column if not exists payment_method text;

  alter table public.orders
    add column if not exists discount_amount numeric(14, 2) not null default 0;

  alter table public.orders
    add column if not exists tax_amount numeric(14, 2) not null default 0;

  alter table public.orders
    add column if not exists completed_at timestamptz;

  alter table public.orders
    add column if not exists cancelled_at timestamptz;

  do $$
  begin
    if not exists (
      select 1 from pg_constraint where conname = 'orders_payment_status_allowed'
    ) then
      alter table public.orders
        add constraint orders_payment_status_allowed
          check (payment_status in ('unpaid', 'partial', 'paid', 'refunded'));
    end if;
  end $$;

  do $$
  begin
    if not exists (
      select 1 from pg_constraint where conname = 'orders_payment_method_allowed'
    ) then
      alter table public.orders
        add constraint orders_payment_method_allowed
          check (
            payment_method is null
            or payment_method in ('cash', 'card', 'bank_transfer', 'wallet', 'credit')
          );
    end if;
  end $$;

  do $$
  begin
    if not exists (
      select 1 from pg_constraint where conname = 'orders_discount_amount_non_negative'
    ) then
      alter table public.orders
        add constraint orders_discount_amount_non_negative
          check (discount_amount >= 0);
    end if;
  end $$;

  do $$
  begin
    if not exists (
      select 1 from pg_constraint where conname = 'orders_tax_amount_non_negative'
    ) then
      alter table public.orders
        add constraint orders_tax_amount_non_negative
          check (tax_amount >= 0);
    end if;
  end $$;

  create index if not exists orders_company_payment_status_idx
    on public.orders (company_id, payment_status)
    where deleted_at is null;

  comment on column public.orders.payment_status is
    'unpaid | partial | paid | refunded — Payments module owns settlement history.';
  comment on column public.orders.payment_method is
    'cash | card | bank_transfer | wallet | credit — intent at sale; ledger comes later.';
  comment on column public.orders.discount_amount is
    'Order-level discount amount (line discounts live on order_items).';
  comment on column public.orders.tax_amount is
    'Reserved for tax engine; Phase 1 defaults to 0.';

  -- ---------------------------------------------------------------------------
  -- Order number allocator
  -- ---------------------------------------------------------------------------

  create or replace function public.next_order_number(p_company_id uuid)
  returns text
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    seq bigint;
    stamp text := to_char(timezone('utc', now()), 'YYYYMMDD');
  begin
    if p_company_id is distinct from public.current_company_id() then
      raise exception 'Forbidden';
    end if;

    select count(*) + 1
      into seq
    from public.orders
    where company_id = p_company_id
      and ordered_at::date = timezone('utc', now())::date;

    return 'SO-' || stamp || '-' || lpad(seq::text, 4, '0');
  end;
  $$;

  revoke all on function public.next_order_number(uuid) from public;
  grant execute on function public.next_order_number(uuid) to authenticated;

  -- ---------------------------------------------------------------------------
  -- Complete order (draft → completed): stock out + purchase signals
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
      insert into public.inventory (
        company_id,
        branch_id,
        product_id,
        quantity,
        created_by,
        updated_by
      )
      values (
        o.company_id,
        o.branch_id,
        item.product_id,
        0,
        emp,
        emp
      )
      on conflict (company_id, branch_id, product_id) do nothing;

      update public.inventory
      set
        quantity = quantity - item.quantity,
        updated_by = emp
      where company_id = o.company_id
        and branch_id = o.branch_id
        and product_id = item.product_id;

      if not found then
        raise exception 'Unable to update inventory for a product on this order.';
      end if;
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
      -- Credit / unpaid intent — receivable increases; Payments settles later.
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

  alter table public.orders enable row level security;
  alter table public.order_items enable row level security;

  drop policy if exists "orders_select_own_company" on public.orders;
  create policy "orders_select_own_company"
    on public.orders
    for select
    to authenticated
    using (company_id = public.current_company_id() and deleted_at is null);

  drop policy if exists "orders_insert_own_company" on public.orders;
  create policy "orders_insert_own_company"
    on public.orders
    for insert
    to authenticated
    with check (
      company_id = public.current_company_id()
      and created_by = public.current_employee_id()
      and updated_by = public.current_employee_id()
    );

  drop policy if exists "orders_update_own_company" on public.orders;
  create policy "orders_update_own_company"
    on public.orders
    for update
    to authenticated
    using (company_id = public.current_company_id() and deleted_at is null)
    with check (
      company_id = public.current_company_id()
      and updated_by = public.current_employee_id()
    );

  drop policy if exists "order_items_select_own_company" on public.order_items;
  create policy "order_items_select_own_company"
    on public.order_items
    for select
    to authenticated
    using (company_id = public.current_company_id());

  drop policy if exists "order_items_insert_own_company" on public.order_items;
  create policy "order_items_insert_own_company"
    on public.order_items
    for insert
    to authenticated
    with check (
      company_id = public.current_company_id()
      and created_by = public.current_employee_id()
      and updated_by = public.current_employee_id()
    );

  drop policy if exists "order_items_update_own_company" on public.order_items;
  create policy "order_items_update_own_company"
    on public.order_items
    for update
    to authenticated
    using (company_id = public.current_company_id())
    with check (
      company_id = public.current_company_id()
      and updated_by = public.current_employee_id()
    );

  drop policy if exists "order_items_delete_own_company" on public.order_items;
  create policy "order_items_delete_own_company"
    on public.order_items
    for delete
    to authenticated
    using (company_id = public.current_company_id());
