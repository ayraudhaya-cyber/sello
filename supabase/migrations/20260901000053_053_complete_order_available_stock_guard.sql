-- Server-side available-stock guard on order completion (tenant setting).

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
  customer_row public.customers%rowtype;
  method text;
  payment_id uuid;
  payment_no text;
  settle boolean := false;
  allow_above boolean := false;
  on_hand numeric(14, 3);
  reserved numeric(14, 3);
  available numeric(14, 3);
  product_name text;
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

  if o.total is null or o.total <= 0 then
    raise exception 'Order total must be greater than zero.';
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

  select coalesce(cs.allow_orders_above_available_stock, false)
    into allow_above
  from public.company_settings cs
  where cs.company_id = company;

  for item in
    select * from public.order_items where order_id = o.id
  loop
    if not allow_above then
      select
        coalesce(i.quantity, 0),
        coalesce(i.reserved_quantity, 0)
      into on_hand, reserved
      from public.inventory i
      where i.company_id = company
        and i.branch_id = o.branch_id
        and i.product_id = item.product_id;

      available := on_hand - reserved;
      if available < 0 then
        available := 0;
      end if;

      if item.quantity > available then
        select p.name into product_name
        from public.products p
        where p.id = item.product_id
          and p.company_id = company;

        raise exception
          'Not enough stock for %. Only % available.',
          coalesce(product_name, 'product'),
          available;
      end if;
    end if;

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

  if settle then
    update public.orders
    set
      status = 'completed',
      payment_status = 'paid',
      completed_at = timezone('utc', now()),
      updated_by = emp
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
        'Recorded on order completion',
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
      status = 'completed',
      payment_status = 'unpaid',
      payment_method = coalesce(nullif(method, ''), 'credit'),
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
    where id = o.customer_id;
  end if;
end;
$$;

revoke all on function public.complete_sales_order(uuid) from public;
grant execute on function public.complete_sales_order(uuid) to authenticated;
