-- Attach remaining unallocated amount of an existing cheque payment to one
-- order. Does not create a payment or cheque, and does not re-apply AR/wallet
-- (those already ran when the cheque payment was completed / will run on
-- approve when it is still pending).

create or replace function public.allocate_cheque_payment_to_order(
  p_cheque_id uuid,
  p_order_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
  pay public.payments%rowtype;
  order_row public.orders%rowtype;
  already numeric(14, 2);
  unallocated numeric(14, 2);
  remaining numeric(14, 2);
  apply_amount numeric(14, 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status in ('bounced', 'cancelled') then
    raise exception 'This cheque cannot be applied to an order.';
  end if;

  if ch.payment_id is null then
    raise exception 'This cheque has no payment to apply.';
  end if;

  select * into pay
  from public.payments
  where id = ch.payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque payment not found.';
  end if;

  if pay.customer_id is distinct from ch.customer_id then
    raise exception 'Cheque payment does not belong to this customer.';
  end if;

  if pay.status not in ('completed', 'pending') then
    raise exception 'Only completed or pending cheque payments can be applied.';
  end if;

  select * into order_row
  from public.orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if order_row.customer_id is distinct from ch.customer_id then
    raise exception 'Cheque and order belong to different customers.';
  end if;

  remaining := public._receivable_allocation_remaining(
    company,
    ch.customer_id,
    p_order_id,
    null,
    null
  );

  if remaining <= 0.001 then
    return 0;
  end if;

  select coalesce(sum(pa.amount), 0)
    into already
  from public.payment_allocations pa
  where pa.payment_id = pay.id
    and pa.order_id = p_order_id;

  if already > 0.001 then
    return already;
  end if;

  select pay.amount - coalesce(sum(pa.amount), 0)
    into unallocated
  from public.payment_allocations pa
  where pa.payment_id = pay.id;

  if unallocated is null then
    unallocated := pay.amount;
  end if;

  if unallocated <= 0.001 then
    raise exception 'This cheque is already fully allocated.';
  end if;

  apply_amount := least(unallocated, remaining);

  insert into public.payment_allocations (
    company_id,
    payment_id,
    order_id,
    amount,
    created_by,
    updated_by
  )
  values (
    company,
    pay.id,
    p_order_id,
    apply_amount,
    emp,
    emp
  );

  perform public.refresh_order_payment_status(p_order_id);

  return apply_amount;
end;
$$;

revoke all on function public.allocate_cheque_payment_to_order(uuid, uuid)
  from public;
grant execute on function public.allocate_cheque_payment_to_order(uuid, uuid)
  to authenticated;

comment on function public.allocate_cheque_payment_to_order(uuid, uuid) is
  'Links leftover unallocated cheque payment amount to one order. Does not create a second cheque or payment.';
