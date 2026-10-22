-- =============================================================================
-- 124 — Return follow-ups
--
-- A payment waiting for approval blocks the return until it is approved or
-- rejected. Invoice correction stops once any unit has been returned.
-- A return recorded today can be cancelled: stock, outstanding, cash, and
-- wallet go back, and the note stays as Cancelled.
-- =============================================================================

alter table public.order_returns
  add column if not exists status text not null default 'recorded';

alter table public.order_returns
  add column if not exists cancelled_at timestamptz;

alter table public.order_returns
  drop constraint if exists order_returns_status_allowed;

alter table public.order_returns
  add constraint order_returns_status_allowed
    check (status in ('recorded', 'cancelled'));

comment on column public.order_returns.status is
  'recorded | cancelled. A cancelled note stays for reference.';

-- Active returns only. A cancelled note must not keep the order marked refunded.
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
    and r.deleted_at is null
    and r.status = 'recorded';

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

-- Block the whole return while a collection is waiting for approval.
-- An uncleared cheque still allows a return that only reduces what they owe.
-- Written in full so it does not depend on how the earlier function was stored.
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

  if fig.approval_waiting then
    raise exception 'A payment on this order is still waiting for approval. Open Payments, approve or reject that payment, then record the return.';
  end if;

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
  elsif fig.cheque_waiting then
    raise exception 'A cheque on this order has not cleared yet. Clear it on Payments before giving money back or saving it. You can still return only what they have not paid.';
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

-- Invoice prices stay once a return has used them.
-- Exact text replace, so a formatting difference cannot skip the guard.
do $migration$
declare
  def text;
  updated text;
  guard constant text := 'oi.returned_quantity > 0';
  marker constant text := 'raise exception ''Cancelled invoices cannot be corrected.'';';
begin
  select pg_get_functiondef(
    'public.correct_invoice(uuid,jsonb)'::regprocedure
  )
  into def;

  if position(guard in def) > 0 then
    return;
  end if;

  updated := replace(
    def,
    marker,
    marker || E'\n'
    || '  if exists (' || E'\n'
    || '    select 1' || E'\n'
    || '    from public.order_items oi' || E'\n'
    || '    where oi.order_id = o.id' || E'\n'
    || '      and oi.returned_quantity > 0' || E'\n'
    || '  ) then' || E'\n'
    || '    raise exception ''This invoice has returned items, so the prices cannot be changed. If the return was recorded today, cancel it on Orders, under Returns, then correct the invoice.'';' || E'\n'
    || '  end if;'
  );

  if updated = def then
    raise exception 'Could not stop invoice correction after a return.';
  end if;

  execute updated;
end;
$migration$;

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

revoke all on function public.cancel_order_return(uuid) from public;
grant execute on function public.cancel_order_return(uuid) to authenticated;

comment on function public.cancel_order_return(uuid) is
  'Same-day undo of a return. Restores stock, outstanding, and any cash or wallet settlement. The note stays as cancelled.';
