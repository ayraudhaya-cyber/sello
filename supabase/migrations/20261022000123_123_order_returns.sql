-- =============================================================================
-- 123 — Return delivered items
--
-- A return is only for units the customer already received. Undelivered units
-- stay on cancel_order_remaining.
--
-- Money: unpaid value comes off customer outstanding. Anything already paid is
-- either given back (a refund row, original collection kept) or saved on the
-- wallet. Stock comes back only when the goods can be sold again.
-- =============================================================================

alter table public.order_items
  add column if not exists returned_quantity numeric(14, 3) not null default 0;

alter table public.order_items
  drop constraint if exists order_items_returned_within_delivered;

alter table public.order_items
  add constraint order_items_returned_within_delivered
    check (
      returned_quantity >= 0
      and returned_quantity <= delivered_quantity
    );

comment on column public.order_items.returned_quantity is
  'Units the customer brought back. Delivered quantity stays as what left the branch.';

-- Net of returns, so a later delivery does not put returned value back on AR.
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
    oi.line_total
    * greatest(oi.delivered_quantity - oi.returned_quantity, 0)
    / nullif(oi.quantity, 0)
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
  'Order total still with the customer: delivered quantity minus returns. Discount and tax follow that share.';

-- ---------------------------------------------------------------------------
-- Return notes
-- ---------------------------------------------------------------------------

create table if not exists public.order_returns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  order_id uuid not null references public.orders (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete restrict,
  employee_id uuid references public.employees (id) on delete set null,
  payment_id uuid references public.payments (id) on delete set null,
  return_number text not null,
  order_number text not null,
  customer_name text not null,
  return_value numeric(14, 2) not null,
  owed_reduction numeric(14, 2) not null default 0,
  paid_portion numeric(14, 2) not null default 0,
  paid_destination text not null default 'none',
  restock boolean not null default true,
  returned_at timestamptz not null default timezone('utc', now()),
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint order_returns_number_not_blank
    check (length(trim(return_number)) > 0),
  constraint order_returns_order_number_not_blank
    check (length(trim(order_number)) > 0),
  constraint order_returns_customer_name_not_blank
    check (length(trim(customer_name)) > 0),
  constraint order_returns_value_positive
    check (return_value > 0),
  constraint order_returns_owed_non_negative
    check (owed_reduction >= 0),
  constraint order_returns_paid_non_negative
    check (paid_portion >= 0),
  constraint order_returns_split_matches
    check (abs(return_value - owed_reduction - paid_portion) < 0.02),
  constraint order_returns_destination_allowed
    check (paid_destination in ('none', 'cash', 'wallet')),
  constraint order_returns_destination_when_paid
    check (
      (paid_portion <= 0.001 and paid_destination = 'none')
      or (paid_portion > 0.001 and paid_destination in ('cash', 'wallet'))
    )
);

create unique index if not exists order_returns_company_number_active_key
  on public.order_returns (company_id, return_number)
  where deleted_at is null;

create index if not exists order_returns_company_returned_at_idx
  on public.order_returns (company_id, returned_at desc)
  where deleted_at is null;

create index if not exists order_returns_order_id_idx
  on public.order_returns (order_id)
  where deleted_at is null;

create trigger trg_order_returns_set_updated_at
before update on public.order_returns
for each row execute function public.set_updated_at();

create table if not exists public.order_return_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  return_id uuid not null references public.order_returns (id) on delete cascade,
  order_item_id uuid not null references public.order_items (id) on delete restrict,
  quantity numeric(14, 3) not null,
  line_value numeric(14, 2) not null default 0,
  created_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),

  constraint order_return_lines_quantity_positive
    check (quantity > 0),
  constraint order_return_lines_value_non_negative
    check (line_value >= 0),
  constraint order_return_lines_return_item_key unique (return_id, order_item_id)
);

create index if not exists order_return_lines_order_item_idx
  on public.order_return_lines (order_item_id);

alter table public.order_returns enable row level security;
alter table public.order_return_lines enable row level security;

drop policy if exists "order_returns_select_own_company" on public.order_returns;
create policy "order_returns_select_own_company"
  on public.order_returns
  for select
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

drop policy if exists "order_return_lines_select_own_company" on public.order_return_lines;
create policy "order_return_lines_select_own_company"
  on public.order_return_lines
  for select
  to authenticated
  using (company_id = public.current_company_id());

comment on table public.order_returns is
  'Goods the customer brought back from a delivered order. One note per return.';

-- A full return settles the order. Partial returns keep the usual unpaid/paid split
-- against the value still with the customer.
create or replace function public.refresh_order_payment_status(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o_total numeric(14, 2);
  allocated numeric(14, 2);
  returned numeric(14, 2);
  net numeric(14, 2);
begin
  select total into o_total
  from public.orders
  where id = p_order_id
    and deleted_at is null;

  if o_total is null then
    return;
  end if;

  select coalesce(sum(pa.amount), 0)
    into allocated
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = p_order_id
    and p.deleted_at is null
    and p.status = 'completed';

  select coalesce(sum(r.return_value), 0)
    into returned
  from public.order_returns r
  where r.order_id = p_order_id
    and r.deleted_at is null;

  if returned > 0.001 then
    net := public.order_delivered_financial_value(p_order_id);
    update public.orders
    set payment_status = case
      when net <= 0.001 then 'refunded'
      when allocated <= 0 then 'unpaid'
      when allocated + 0.001 >= net then 'paid'
      else 'partial'
    end
    where id = p_order_id;
    return;
  end if;

  update public.orders
  set payment_status = case
    when allocated <= 0 then 'unpaid'
    when allocated + 0.001 >= o_total then 'paid'
    else 'partial'
  end
  where id = p_order_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared figures for the return screen
-- ---------------------------------------------------------------------------

create or replace function public._order_return_figures(p_order_id uuid)
returns table (
  net_delivered numeric,
  amount_paid numeric,
  still_owed numeric,
  approval_waiting boolean,
  cheque_waiting boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
  net numeric(14, 2);
  paid numeric(14, 2);
begin
  if company is null then
    raise exception 'Session context missing.';
  end if;

  if not exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and o.company_id = company
      and o.deleted_at is null
  ) then
    raise exception 'Order not found.';
  end if;

  net := public.order_delivered_financial_value(p_order_id);

  select coalesce(sum(pa.amount), 0)
    into paid
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = p_order_id
    and p.deleted_at is null
    and p.status = 'completed';

  return query
  select
    net,
    paid,
    greatest(net - paid, 0)::numeric(14, 2),
    exists (
      select 1
      from public.payment_allocations pa
      join public.payments p on p.id = pa.payment_id
      where pa.order_id = p_order_id
        and p.deleted_at is null
        and p.status = 'pending'
    ),
    exists (
      select 1
      from public.payment_allocations pa
      join public.payments p on p.id = pa.payment_id
      join public.cheques ch on ch.payment_id = p.id
      where pa.order_id = p_order_id
        and p.deleted_at is null
        and p.status = 'completed'
        and ch.deleted_at is null
        and ch.status in ('awaiting_collection', 'collected', 'deposited')
    );
end;
$$;

revoke all on function public._order_return_figures(uuid) from public;

create or replace function public.return_order_context(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fig record;
begin
  select * into fig from public._order_return_figures(p_order_id);
  return jsonb_build_object(
    'net_delivered', fig.net_delivered,
    'amount_paid', fig.amount_paid,
    'still_owed', fig.still_owed,
    'approval_waiting', fig.approval_waiting,
    'cheque_waiting', fig.cheque_waiting
  );
end;
$$;

revoke all on function public.return_order_context(uuid) from public;
grant execute on function public.return_order_context(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Record the return
-- p_lines: [{ "order_item_id": "...", "quantity": 1 }]
-- p_destination: none | cash | wallet
-- ---------------------------------------------------------------------------

create or replace function public.return_order_items(
  p_order_id uuid,
  p_lines jsonb,
  p_destination text default 'none',
  p_restock boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  customer_name text;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  fig record;
  item public.order_items%rowtype;
  line_rec record;
  return_qty numeric(14, 3);
  available numeric(14, 3);
  share numeric(14, 6);
  share_sum numeric(14, 6) := 0;
  return_value numeric(14, 2);
  owed numeric(14, 2);
  paid_part numeric(14, 2);
  destination text;
  return_id uuid;
  return_no text;
  seq bigint;
  stamp text;
  allocated numeric(14, 2) := 0;
  line_count integer := 0;
  line_index integer := 0;
  line_value numeric(14, 2);
  refund_payment_id uuid;
  payment_no text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_lines is null
     or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception 'Enter at least one quantity to return.';
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

  if o.status not in ('placed', 'partially_delivered', 'completed') then
    raise exception 'Only delivered items can be returned.';
  end if;

  select c.name into customer_name
  from public.customers c
  where c.id = o.customer_id
    and c.company_id = company
    and c.deleted_at is null;

  if customer_name is null then
    raise exception 'Customer not found.';
  end if;

  -- Validate and measure the share before writing.
  for line_rec in
    select
      (elem->>'order_item_id')::uuid as order_item_id,
      (elem->>'quantity')::numeric as quantity
    from jsonb_array_elements(p_lines) as elem
  loop
    if line_rec.order_item_id is null then
      raise exception 'Each return line needs an item.';
    end if;

    return_qty := coalesce(line_rec.quantity, 0);
    if return_qty <= 0 then
      raise exception 'Return quantity must be greater than zero.';
    end if;

    select * into item
    from public.order_items
    where id = line_rec.order_item_id
      and order_id = o.id
    for update;

    if not found then
      raise exception 'Order line not found on this order.';
    end if;

    available := item.delivered_quantity - item.returned_quantity;
    if return_qty > available + 0.0001 then
      raise exception
        'Cannot return % ; only % can still come back.',
        return_qty,
        greatest(available, 0);
    end if;

    if item.quantity <= 0 then
      raise exception 'Order line quantity is invalid.';
    end if;

    share := item.line_total * return_qty / item.quantity;
    share_sum := share_sum + share;
    line_count := line_count + 1;
  end loop;

  if o.subtotal is null or o.subtotal <= 0 or o.total is null or o.total <= 0 then
    raise exception 'This order has no value to return.';
  end if;

  return_value := round((o.total * share_sum / o.subtotal)::numeric, 2);
  if return_value <= 0.001 then
    raise exception 'Enter at least one quantity to return.';
  end if;

  select * into fig from public._order_return_figures(o.id);
  owed := least(return_value, fig.still_owed);
  paid_part := round((return_value - owed)::numeric, 2);
  owed := round((return_value - paid_part)::numeric, 2);

  destination := coalesce(nullif(trim(p_destination), ''), 'none');
  if paid_part <= 0.001 then
    destination := 'none';
    paid_part := 0;
    owed := return_value;
  elsif destination not in ('cash', 'wallet') then
    raise exception 'Choose where the paid amount goes.';
  elsif fig.approval_waiting then
    raise exception 'A payment on this order is still waiting for approval.';
  elsif fig.cheque_waiting then
    raise exception 'A cheque on this order has not cleared yet.';
  end if;

  stamp := to_char(timezone('utc', now()), 'YYYYMMDD');
  select count(*) + 1
    into seq
  from public.order_returns r
  where r.company_id = company
    and r.returned_at::date = timezone('utc', now())::date;

  return_no := 'RT-' || stamp || '-' || lpad(seq::text, 4, '0');

  insert into public.order_returns (
    company_id,
    branch_id,
    order_id,
    customer_id,
    employee_id,
    return_number,
    order_number,
    customer_name,
    return_value,
    owed_reduction,
    paid_portion,
    paid_destination,
    restock,
    created_by,
    updated_by
  )
  values (
    company,
    o.branch_id,
    o.id,
    o.customer_id,
    o.employee_id,
    return_no,
    o.order_number,
    customer_name,
    return_value,
    owed,
    paid_part,
    destination,
    coalesce(p_restock, true),
    emp,
    emp
  )
  returning id into return_id;

  for line_rec in
    select
      (elem->>'order_item_id')::uuid as order_item_id,
      (elem->>'quantity')::numeric as quantity
    from jsonb_array_elements(p_lines) as elem
  loop
    line_index := line_index + 1;
    return_qty := line_rec.quantity;

    select * into item
    from public.order_items
    where id = line_rec.order_item_id
      and order_id = o.id
    for update;

    share := item.line_total * return_qty / item.quantity;
    if line_index = line_count then
      line_value := round((return_value - allocated)::numeric, 2);
    else
      line_value := round((return_value * share / share_sum)::numeric, 2);
      allocated := allocated + line_value;
    end if;

    insert into public.order_return_lines (
      company_id,
      return_id,
      order_item_id,
      quantity,
      line_value,
      created_by
    )
    values (
      company,
      return_id,
      item.id,
      return_qty,
      greatest(line_value, 0),
      emp
    );

    update public.order_items
    set
      returned_quantity = returned_quantity + return_qty,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = item.id;

    if coalesce(p_restock, true) then
      perform public.adjust_inventory(
        o.branch_id,
        item.product_id,
        return_qty,
        'return',
        'Customer return ' || return_no,
        o.order_number,
        'order_return',
        return_id,
        item.variant_id
      );
    end if;
  end loop;

  update public.orders
  set
    recognized_receivable_value = public.order_delivered_financial_value(o.id),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

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
      return_no,
      'Given back for ' || return_no || ' on ' || o.order_number,
      timezone('utc', now()),
      emp,
      emp
    )
    returning id into refund_payment_id;

    update public.order_returns
    set payment_id = refund_payment_id
    where id = return_id;
  end if;

  perform public.refresh_order_payment_status(o.id);

  return jsonb_build_object(
    'id', return_id,
    'return_number', return_no,
    'return_value', return_value,
    'owed_reduction', owed,
    'paid_portion', paid_part,
    'paid_destination', destination,
    'restock', coalesce(p_restock, true)
  );
end;
$$;

revoke all on function public.return_order_items(uuid, jsonb, text, boolean) from public;
grant execute on function public.return_order_items(uuid, jsonb, text, boolean) to authenticated;
