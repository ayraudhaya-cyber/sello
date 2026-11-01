-- Mark a mistaken delivery as not delivered yet, and cancel an order at any time.
--
-- Not delivered: stock for the delivered units comes back, what they owe drops
-- by that unpaid value, and the order returns to placed. Payments stay on the
-- order. Nothing is cancelled.
--
-- Cancel: the order stops. Undelivered units are closed. Delivered units that
-- are still with the customer go back to stock. What they still owe is cleared.
-- Money already paid is given back or added to their wallet.

alter table public.orders
  add column if not exists cancellation_reason text;

alter table public.orders
  add column if not exists cancellation_paid_destination text;

alter table public.orders
  add column if not exists cancellation_paid_amount numeric(14, 2) not null default 0;

alter table public.orders
  drop constraint if exists orders_cancellation_paid_destination_allowed;

alter table public.orders
  add constraint orders_cancellation_paid_destination_allowed check (
    cancellation_paid_destination is null
    or cancellation_paid_destination in ('none', 'cash', 'wallet')
  );

alter table public.orders
  drop constraint if exists orders_cancellation_paid_amount_non_negative;

alter table public.orders
  add constraint orders_cancellation_paid_amount_non_negative
  check (cancellation_paid_amount >= 0);

comment on column public.orders.cancellation_reason is
  'Why the order was cancelled. Empty while the order is still open.';

comment on column public.orders.cancellation_paid_destination is
  'none | cash | wallet. Where money already paid went when the order was cancelled.';

comment on column public.orders.cancellation_paid_amount is
  'Money already paid that was given back or added to the wallet when the order was cancelled.';

-- ---------------------------------------------------------------------------
-- Mark delivered units as not delivered yet. The order stays open.
-- ---------------------------------------------------------------------------

create or replace function public.mark_order_not_delivered(p_order_id uuid)
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
  put_back numeric(14, 3);
  any_delivered boolean := false;
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

  if o.status not in ('partially_delivered', 'completed') then
    raise exception 'This order is already not delivered.';
  end if;

  if exists (
    select 1
    from public.order_items oi
    where oi.order_id = o.id
      and oi.returned_quantity > 0
  ) then
    raise exception 'This order has returned items. Cancel that return on Orders, under Returns, then mark the order as not delivered.';
  end if;

  if exists (
    select 1
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = o.id
      and p.deleted_at is null
      and p.status = 'pending'
  ) then
    raise exception 'A payment on this order is still waiting for approval. Open Payments, approve or reject it, then mark the order as not delivered.';
  end if;

  for item in
    select * from public.order_items where order_id = o.id for update
  loop
    put_back := item.delivered_quantity;
    if put_back <= 0 then
      continue;
    end if;

    any_delivered := true;

    perform public.adjust_inventory(
      o.branch_id,
      item.product_id,
      put_back,
      'correction',
      'Marked as not delivered',
      o.order_number,
      'order',
      o.id,
      item.variant_id
    );

    update public.order_items
    set
      delivered_quantity = 0,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = item.id;
  end loop;

  if not any_delivered then
    raise exception 'This order is already not delivered.';
  end if;

  -- Payments stay allocated to this order. Only the unpaid delivered value
  -- comes off what the customer owes.
  perform public.apply_order_fulfillment_receivable(o.id);

  update public.orders
  set
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.refresh_order_fulfillment_status(o.id);
end;
$$;

comment on function public.mark_order_not_delivered(uuid) is
  'Puts delivered units back in stock and returns the order to placed. Does not cancel the order or move payments.';

revoke all on function public.mark_order_not_delivered(uuid) from public;
grant execute on function public.mark_order_not_delivered(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Cancel the whole order. Stock and money are updated in this same step.
-- p_destination: none | cash | wallet
-- ---------------------------------------------------------------------------

create or replace function public.cancel_sales_order(
  p_order_id uuid,
  p_destination text default 'none',
  p_reason text default null
)
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
  fig record;
  reason text;
  destination text;
  paid_part numeric(14, 2);
  owed numeric(14, 2);
  put_back numeric(14, 3);
  payment_no text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  reason := nullif(trim(coalesce(p_reason, '')), '');
  if reason is null then
    raise exception 'Write a short reason for cancelling this order.';
  end if;
  if char_length(reason) > 500 then
    raise exception 'Keep the reason shorter than 500 characters.';
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

  if o.status = 'cancelled' then
    return;
  end if;

  if o.status = 'draft' then
    update public.orders
    set
      status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, timezone('utc', now())),
      cancellation_reason = reason,
      cancellation_paid_destination = 'none',
      cancellation_paid_amount = 0,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;
    return;
  end if;

  if o.status not in ('placed', 'partially_delivered', 'completed') then
    raise exception 'This order cannot be cancelled.';
  end if;

  select * into fig from public._order_return_figures(o.id);

  if fig.approval_waiting then
    raise exception 'A payment on this order is still waiting for approval. Open Payments, approve or reject it, then cancel the order.';
  end if;

  paid_part := round(coalesce(fig.amount_paid, 0), 2);
  owed := greatest(
    round(coalesce(fig.still_owed, 0), 2),
    round(
      greatest(
        coalesce(o.recognized_receivable_value, 0) - coalesce(fig.amount_paid, 0),
        0
      ),
      2
    )
  );

  if paid_part > 0.001 and fig.cheque_waiting then
    raise exception 'A cheque on this order has not cleared yet. Finish it on Payments before cancelling. You can give the money back or add it to their wallet after that.';
  end if;

  destination := coalesce(nullif(trim(p_destination), ''), 'none');
  if paid_part <= 0.001 then
    destination := 'none';
    paid_part := 0;
  elsif destination not in ('cash', 'wallet') then
    raise exception 'Choose where the money they already paid goes.';
  end if;

  for item in
    select * from public.order_items where order_id = o.id for update
  loop
    put_back := item.delivered_quantity - item.returned_quantity;
    if put_back > 0 then
      perform public.adjust_inventory(
        o.branch_id,
        item.product_id,
        put_back,
        'correction',
        'Order cancelled',
        o.order_number,
        'order',
        o.id,
        item.variant_id
      );
    end if;

    if item.returned_quantity <= 0 then
      update public.order_items
      set
        delivered_quantity = 0,
        cancelled_quantity = quantity,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    else
      update public.order_items
      set
        cancelled_quantity = quantity - delivered_quantity,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    end if;
  end loop;

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
      o.order_number,
      'Given back when ' || o.order_number || ' was cancelled',
      timezone('utc', now()),
      emp,
      emp
    );
  end if;

  update public.orders
  set
    status = 'cancelled',
    cancelled_at = coalesce(cancelled_at, timezone('utc', now())),
    cancellation_reason = reason,
    cancellation_paid_destination = destination,
    cancellation_paid_amount = paid_part,
    recognized_receivable_value = 0,
    payment_status = case
      when paid_part > 0.001 then 'refunded'
      else payment_status
    end,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;
end;
$$;

comment on function public.cancel_sales_order(uuid, text, text) is
  'Cancels a draft, placed, partially delivered, or completed order. Restocks goods still with the customer, clears what they owe, and gives paid money back or adds it to the wallet.';

revoke all on function public.cancel_sales_order(uuid, text, text) from public;
grant execute on function public.cancel_sales_order(uuid, text, text) to authenticated;
