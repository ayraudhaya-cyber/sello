-- =============================================================================
-- 122 — Customer receipt for applied order collections
--
-- prepare_payment_receipt used to return only when the payment allocated an
-- opening balance. An applied order-only collection then texted the team and
-- stayed silent for the customer. Any completed payment allocated to an order
-- or an opening balance now prepares one receipt. The client adds the order
-- number and the discount line when those values are present.
-- =============================================================================

create or replace function public.prepare_payment_receipt(
  p_payment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_employee_id uuid;
  v_payment public.payments%rowtype;
  v_event_id uuid;
  v_already boolean := false;
  v_customer jsonb;
  v_company_name text;
  v_currency text;
  v_has_opening boolean := false;
  v_has_order boolean := false;
  v_references text;
  v_order_numbers text;
begin
  v_employee_id := public.current_employee_id();
  v_company_id := public.current_company_id();
  if v_employee_id is null or v_company_id is null then
    raise exception 'Session context missing.';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id
    and company_id = v_company_id
    and deleted_at is null;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if v_payment.status is distinct from 'completed' then
    return jsonb_build_object(
      'ok', false,
      'reason', 'not_applied',
      'has_opening_allocation', false,
      'has_order_allocation', false
    );
  end if;

  select exists (
    select 1
    from public.payment_allocations pa
    where pa.payment_id = v_payment.id
      and pa.receivable_adjustment_id is not null
  )
  into v_has_opening;

  select exists (
    select 1
    from public.payment_allocations pa
    where pa.payment_id = v_payment.id
      and pa.order_id is not null
  )
  into v_has_order;

  if not coalesce(v_has_opening, false) and not coalesce(v_has_order, false) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'no_allocation',
      'has_opening_allocation', false,
      'has_order_allocation', false
    );
  end if;

  select string_agg(refs.reference_number, ', ' order by refs.reference_number)
  into v_references
  from (
    select distinct adj.reference_number
    from public.payment_allocations pa
    inner join public.customer_receivable_adjustments adj
      on adj.id = pa.receivable_adjustment_id
    where pa.payment_id = v_payment.id
      and adj.reference_number is not null
  ) refs;

  select string_agg(orders.order_number, ', ' order by orders.order_number)
  into v_order_numbers
  from (
    select distinct o.order_number
    from public.payment_allocations pa
    inner join public.orders o on o.id = pa.order_id
    where pa.payment_id = v_payment.id
      and o.order_number is not null
  ) orders;

  insert into public.outbound_notification_events (
    company_id,
    event_type,
    reference_type,
    reference_id
  ) values (
    v_company_id,
    'receipt',
    'payment',
    v_payment.id
  )
  on conflict (event_type, reference_type, reference_id) do nothing;

  select e.id, e.created_at < timezone('utc', now()) - interval '1 second'
  into v_event_id, v_already
  from public.outbound_notification_events e
  where e.event_type = 'receipt'
    and e.reference_type = 'payment'
    and e.reference_id = v_payment.id;

  if v_event_id is not null
     and exists (
       select 1
       from public.outbound_notification_dispatches d
       where d.event_id = v_event_id
     ) then
    v_already := true;
  end if;

  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'phone', c.phone,
    'whatsapp', c.whatsapp
  )
  into v_customer
  from public.customers c
  where c.id = v_payment.customer_id
    and c.company_id = v_company_id
    and c.deleted_at is null;

  select co.name into v_company_name
  from public.companies co
  where co.id = v_company_id;

  select cs.currency into v_currency
  from public.company_settings cs
  where cs.company_id = v_company_id;

  return jsonb_build_object(
    'ok', true,
    'already_prepared', coalesce(v_already, false),
    'event_id', v_event_id,
    'has_opening_allocation', coalesce(v_has_opening, false),
    'has_order_allocation', coalesce(v_has_order, false),
    'opening_reference', v_references,
    'order_numbers', v_order_numbers,
    'payment', jsonb_build_object(
      'number', v_payment.payment_number,
      'amount', v_payment.amount,
      'discount_amount', coalesce(v_payment.discount_amount, 0),
      'method', v_payment.method,
      'status', v_payment.status,
      'received_at', v_payment.received_at,
      'currency', coalesce(v_currency, 'USD'),
      'customer_name', v_customer ->> 'name',
      'company_name', v_company_name
    ),
    'customer', coalesce(v_customer, 'null'::jsonb)
  );
end;
$$;

comment on function public.prepare_payment_receipt(uuid) is
  'Prepares one customer receipt for a completed payment allocated to an order or an opening balance. Includes discount_amount and order numbers.';
