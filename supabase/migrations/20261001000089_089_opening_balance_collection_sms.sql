-- =============================================================================
-- 089 — Opening-balance collection, old invoice reference, payment SMS
--
-- Optional reference_number on customer_receivable_adjustments (not an order FK).
-- Collections Report surfaces it beside the Sello OB- number.
-- prepare_payment_receipt issues a unique receipt event for completed payments
-- that allocate to an opening-balance adjustment, so applied customer SMS can
-- reuse claim_outbound_sms_dispatch. Pending collections stay on
-- prepare_collection_acknowledgement.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- reference_number
-- ---------------------------------------------------------------------------

alter table public.customer_receivable_adjustments
  add column if not exists reference_number text;

alter table public.customer_receivable_adjustments
  drop constraint if exists customer_receivable_adjustments_reference_not_blank;

alter table public.customer_receivable_adjustments
  add constraint customer_receivable_adjustments_reference_not_blank
  check (
    reference_number is null
    or (
      length(trim(reference_number)) > 0
      and length(trim(reference_number)) <= 80
    )
  );

comment on column public.customer_receivable_adjustments.reference_number is
  'Optional pre-Sello invoice / reference. Not an orders foreign key.';

-- ---------------------------------------------------------------------------
-- record_opening_balance_adjustment — add p_reference_number
-- ---------------------------------------------------------------------------

drop function if exists public.record_opening_balance_adjustment(
  uuid, numeric, text, timestamptz
);

create or replace function public.record_opening_balance_adjustment(
  p_customer_id uuid,
  p_amount numeric,
  p_notes text default null,
  p_recognized_at timestamptz default null,
  p_reference_number text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  customer_row public.customers%rowtype;
  branch uuid;
  adj_id uuid;
  adj_no text;
  amount_value numeric(14, 2);
  recognized timestamptz;
  currency_code text;
  money_label text;
  summary_text text;
  reference_value text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_record_opening_balance_adjustment() then
    raise exception 'Only Owner or Manager can add an opening balance.';
  end if;

  amount_value := round(coalesce(p_amount, 0)::numeric, 2);
  if amount_value <= 0 then
    raise exception 'Opening balance amount must be greater than zero.';
  end if;

  recognized := coalesce(p_recognized_at, timezone('utc', now()));
  if recognized > timezone('utc', now()) + interval '1 day' then
    raise exception 'As-of date cannot be in the future.';
  end if;

  reference_value := nullif(trim(coalesce(p_reference_number, '')), '');
  if reference_value is not null and length(reference_value) > 80 then
    raise exception 'Old invoice / reference is too long.';
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

  if not coalesce(customer_row.is_active, false) then
    raise exception 'Customer is inactive.';
  end if;

  branch := customer_row.branch_id;
  if branch is null then
    select e.branch_id into branch
    from public.employees e
    where e.id = emp
      and e.company_id = company
      and e.deleted_at is null;
  end if;
  if branch is null then
    select b.id into branch
    from public.branches b
    where b.company_id = company
      and b.deleted_at is null
      and b.is_active = true
    order by b.created_at
    limit 1;
  end if;

  adj_no := public.next_opening_balance_number(company);

  insert into public.customer_receivable_adjustments (
    company_id,
    customer_id,
    branch_id,
    adjustment_number,
    kind,
    amount,
    recognized_at,
    notes,
    reference_number,
    created_by
  )
  values (
    company,
    p_customer_id,
    branch,
    adj_no,
    'opening_balance',
    amount_value,
    recognized,
    nullif(trim(coalesce(p_notes, '')), ''),
    reference_value,
    emp
  )
  returning id into adj_id;

  update public.customers
  set
    opening_balance = opening_balance + amount_value,
    current_balance = current_balance + amount_value,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_customer_id
    and company_id = company;

  select coalesce(cs.currency, 'USD')
    into currency_code
  from public.company_settings cs
  where cs.company_id = company
  limit 1;

  money_label := case upper(coalesce(currency_code, 'USD'))
    when 'LKR' then 'Rs '
    when 'USD' then '$'
    when 'EUR' then E'€'
    when 'GBP' then E'£'
    else coalesce(currency_code, '') || ' '
  end;

  summary_text :=
    'Opening balance of '
    || money_label
    || to_char(amount_value, 'FM999999999990.00')
    || ' added for '
    || customer_row.name;

  perform public.log_company_activity(
    company,
    'customers',
    'opening_balance_added',
    summary_text,
    emp,
    null,
    'customer',
    p_customer_id,
    jsonb_build_object(
      'adjustment_id', adj_id,
      'adjustment_number', adj_no,
      'amount', amount_value,
      'reference_number', reference_value
    )
  );

  return adj_id;
end;
$$;

comment on function public.record_opening_balance_adjustment(
  uuid, numeric, text, timestamptz, text
) is
  'Owner/Manager additive opening AR after customer create. '
  'Optional p_reference_number is a pre-Sello invoice label, not an order id.';

revoke all on function public.record_opening_balance_adjustment(
  uuid, numeric, text, timestamptz, text
) from public;
grant execute on function public.record_opening_balance_adjustment(
  uuid, numeric, text, timestamptz, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- Collections Report — keep OB- number; add optional reference_number
-- ---------------------------------------------------------------------------

drop function if exists public.fetch_collections_report(timestamptz, uuid[]);

create or replace function public.fetch_collections_report(
  p_as_of timestamptz,
  p_employee_ids uuid[] default null
)
returns table (
  order_id uuid,
  order_number text,
  ordered_at timestamptz,
  customer_id uuid,
  customer_name text,
  customer_phone text,
  employee_id uuid,
  employee_name text,
  order_total numeric,
  amount_paid numeric,
  open_balance numeric,
  document_type text,
  reference_number text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
  filter_reps boolean :=
    p_employee_ids is not null and cardinality(p_employee_ids) > 0;
begin
  if company is null then
    raise exception 'Session context missing.';
  end if;

  return query
    with paid_orders as (
      select
        pa.order_id,
        coalesce(sum(pa.amount), 0)::numeric(14, 2) as amount_paid
      from public.payment_allocations pa
      inner join public.payments p on p.id = pa.payment_id
      where p.company_id = company
        and p.status = 'completed'
        and p.deleted_at is null
        and p.received_at <= p_as_of
        and pa.order_id is not null
      group by pa.order_id
    ),
    paid_adjustments as (
      select
        pa.receivable_adjustment_id,
        coalesce(sum(pa.amount), 0)::numeric(14, 2) as amount_paid
      from public.payment_allocations pa
      inner join public.payments p on p.id = pa.payment_id
      where p.company_id = company
        and p.status = 'completed'
        and p.deleted_at is null
        and p.received_at <= p_as_of
        and pa.receivable_adjustment_id is not null
      group by pa.receivable_adjustment_id
    )
    select
      o.id,
      o.order_number,
      o.ordered_at,
      c.id,
      c.name,
      nullif(trim(c.phone), ''),
      o.employee_id,
      e.full_name,
      o.total,
      coalesce(paid_orders.amount_paid, 0)::numeric(14, 2),
      (o.total - coalesce(paid_orders.amount_paid, 0))::numeric(14, 2),
      'Invoice'::text,
      null::text
    from public.orders o
    inner join public.customers c on c.id = o.customer_id
    left join public.employees e on e.id = o.employee_id
    left join paid_orders on paid_orders.order_id = o.id
    where o.company_id = company
      and o.deleted_at is null
      and o.status in ('placed', 'partially_delivered', 'completed')
      and o.ordered_at <= p_as_of
      and (
        not filter_reps
        or o.employee_id = any (p_employee_ids)
      )
      and (o.total - coalesce(paid_orders.amount_paid, 0)) > 0.001

    union all

    select
      a.id,
      a.adjustment_number,
      a.recognized_at,
      c.id,
      c.name,
      nullif(trim(c.phone), ''),
      null::uuid,
      '—'::text,
      a.amount,
      coalesce(paid_adjustments.amount_paid, 0)::numeric(14, 2),
      (a.amount - coalesce(paid_adjustments.amount_paid, 0))::numeric(14, 2),
      'Opening balance'::text,
      a.reference_number
    from public.customer_receivable_adjustments a
    inner join public.customers c on c.id = a.customer_id
    left join paid_adjustments on paid_adjustments.receivable_adjustment_id = a.id
    where a.company_id = company
      and a.kind = 'opening_balance'
      and a.recognized_at <= p_as_of
      and not filter_reps
      and (a.amount - coalesce(paid_adjustments.amount_paid, 0)) > 0.001

    order by 5, 3, 2;
end;
$$;

comment on function public.fetch_collections_report(timestamptz, uuid[]) is
  'As-of open invoices plus opening-balance adjustments. '
  'Opening rows keep the Sello OB- number; reference_number is the optional '
  'pre-Sello invoice label. Opening rows are All Sales Reps only.';

revoke all on function public.fetch_collections_report(timestamptz, uuid[])
  from public;
grant execute on function public.fetch_collections_report(timestamptz, uuid[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- prepare_payment_receipt — completed payments allocated to opening AR
-- ---------------------------------------------------------------------------

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
  v_references text;
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
      'has_opening_allocation', false
    );
  end if;

  select exists (
    select 1
    from public.payment_allocations pa
    where pa.payment_id = v_payment.id
      and pa.receivable_adjustment_id is not null
  )
  into v_has_opening;

  if not coalesce(v_has_opening, false) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'no_opening_allocation',
      'has_opening_allocation', false
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
    'has_opening_allocation', true,
    'opening_reference', v_references,
    'payment', jsonb_build_object(
      'number', v_payment.payment_number,
      'amount', v_payment.amount,
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
  'Unique receipt event for a completed payment allocated to opening-balance AR. '
  'Does not change balances. Order-only payments return ok=false.';

revoke all on function public.prepare_payment_receipt(uuid) from public;
grant execute on function public.prepare_payment_receipt(uuid) to authenticated;
