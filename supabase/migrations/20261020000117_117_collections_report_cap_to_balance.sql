-- =============================================================================
-- 117 — Still to collect cannot exceed customer Outstanding
--
-- Invoice/OB open lines (recognized − allocations) can sum higher than
-- customers.current_balance when completed collections reduced AR without a
-- matching allocation. Payments Outstanding is the source of truth.
--
-- When no sales-rep filter is applied, each customer's open lines are reduced
-- oldest-first so they cannot exceed that customer's current_balance.
-- Rep-filtered exports stay invoice-level (balance is not per-rep).
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
    ),
    raw_rows as (
      select
        o.id as doc_id,
        o.order_number as doc_number,
        o.ordered_at as doc_at,
        c.id as cust_id,
        c.name as cust_name,
        nullif(trim(c.phone), '') as cust_phone,
        o.employee_id as emp_id,
        e.full_name as emp_name,
        coalesce(o.recognized_receivable_value, 0)::numeric(14, 2) as doc_total,
        coalesce(paid_orders.amount_paid, 0)::numeric(14, 2) as paid_total,
        (
          coalesce(o.recognized_receivable_value, 0)
          - coalesce(paid_orders.amount_paid, 0)
        )::numeric(14, 2) as raw_open,
        'Invoice'::text as doc_type,
        null::text as ref_number,
        greatest(c.current_balance, 0)::numeric(14, 2) as cust_balance
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
        a.reference_number,
        greatest(c.current_balance, 0)::numeric(14, 2)
      from public.customer_receivable_adjustments a
      inner join public.customers c on c.id = a.customer_id
      left join paid_adjustments
        on paid_adjustments.receivable_adjustment_id = a.id
      where a.company_id = company
        and a.kind = 'opening_balance'
        and a.reversed_at is null
        and a.recognized_at <= p_as_of
        and c.deleted_at is null
        and c.is_active = true
        and not filter_reps
        and (a.amount - coalesce(paid_adjustments.amount_paid, 0)) > 0.001
    ),
    ranked as (
      select
        r.*,
        coalesce(
          sum(r.raw_open) over (
            partition by r.cust_id
            order by r.doc_at, r.doc_number, r.doc_id
            rows between unbounded preceding and 1 preceding
          ),
          0
        )::numeric(14, 2) as prior_open
      from raw_rows r
    ),
    capped as (
      select
        ranked.doc_id,
        ranked.doc_number,
        ranked.doc_at,
        ranked.cust_id,
        ranked.cust_name,
        ranked.cust_phone,
        ranked.emp_id,
        ranked.emp_name,
        ranked.doc_total,
        ranked.paid_total,
        ranked.doc_type,
        ranked.ref_number,
        case
          when filter_reps then ranked.raw_open
          else greatest(
            least(
              ranked.raw_open,
              greatest(ranked.cust_balance - ranked.prior_open, 0)
            ),
            0
          )::numeric(14, 2)
        end as capped_open
      from ranked
    )
    select
      capped.doc_id,
      capped.doc_number,
      capped.doc_at,
      capped.cust_id,
      capped.cust_name,
      capped.cust_phone,
      capped.emp_id,
      capped.emp_name,
      capped.doc_total,
      capped.paid_total,
      capped.capped_open,
      capped.doc_type,
      capped.ref_number
    from capped
    where capped.capped_open > 0.001
    order by 5, 3, 2;
end;
$$;

comment on function public.fetch_collections_report(timestamptz, uuid[]) is
  'Open recognized AR and opening balances, capped per customer to current_balance '
  'when listing all sales reps so the grand total matches Payments Outstanding.';

revoke all on function public.fetch_collections_report(timestamptz, uuid[])
  from public;
grant execute on function public.fetch_collections_report(timestamptz, uuid[])
  to authenticated;
