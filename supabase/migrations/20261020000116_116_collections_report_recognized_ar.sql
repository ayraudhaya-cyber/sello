-- =============================================================================
-- 116 — Still to collect uses recognized AR only (true Outstanding basis)
--
-- 115 used greatest(delivered_value, recognized_receivable_value). Delivered
-- quantity can exist on older orders that never posted to customers.current_
-- balance, so the export stayed higher than Payments Outstanding.
--
-- Open invoice balance is now:
--   greatest(recognized_receivable_value − completed allocations, 0)
-- Opening balances unchanged. Same active-customer filter as 115.
-- =============================================================================

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
      coalesce(o.recognized_receivable_value, 0)::numeric(14, 2),
      coalesce(paid_orders.amount_paid, 0)::numeric(14, 2),
      (
        coalesce(o.recognized_receivable_value, 0)
        - coalesce(paid_orders.amount_paid, 0)
      )::numeric(14, 2),
      'Invoice'::text,
      null::text
    from public.orders o
    inner join public.customers c on c.id = o.customer_id
    left join public.employees e on e.id = o.employee_id
    left join paid_orders on paid_orders.order_id = o.id
    where o.company_id = company
      and o.deleted_at is null
      and c.deleted_at is null
      and c.is_active = true
      and o.status in ('placed', 'partially_delivered', 'completed')
      and o.ordered_at <= p_as_of
      and (
        not filter_reps
        or o.employee_id = any (p_employee_ids)
      )
      and (
        coalesce(o.recognized_receivable_value, 0)
        - coalesce(paid_orders.amount_paid, 0)
      ) > 0.001

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
      and a.reversed_at is null
      and a.recognized_at <= p_as_of
      and c.deleted_at is null
      and c.is_active = true
      and not filter_reps
      and (a.amount - coalesce(paid_adjustments.amount_paid, 0)) > 0.001

    order by 5, 3, 2;
end;
$$;

comment on function public.fetch_collections_report(timestamptz, uuid[]) is
  'Open balances from recognized receivable (posted AR) and opening balances. '
  'Does not invent AR from delivered qty that never hit customers.current_balance.';

revoke all on function public.fetch_collections_report(timestamptz, uuid[])
  from public;
grant execute on function public.fetch_collections_report(timestamptz, uuid[])
  to authenticated;
