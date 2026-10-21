-- =============================================================================
-- 118 — Still to collect includes residual customer Outstanding
--
-- After capping invoice/OB lines to current_balance (117), a small gap can
-- remain: customers who still owe on the ledger but have no open recognized
-- invoice or opening-balance adjustment line (or lines sum to less than the
-- balance). That made Payments Outstanding a few thousand higher than the
-- export grand total.
--
-- When listing all sales reps, add one "Other outstanding" row per customer
-- for max(current_balance − open lines, 0) so the grand total ties.
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
        ranked.cust_balance,
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
    ),
    line_rows as (
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
        capped.capped_open as open_amt,
        capped.doc_type,
        capped.ref_number
      from capped
      where capped.capped_open > 0.001
    ),
    covered as (
      select
        line_rows.cust_id,
        coalesce(sum(line_rows.open_amt), 0)::numeric(14, 2) as covered
      from line_rows
      group by line_rows.cust_id
    ),
    residual_rows as (
      select
        c.id as doc_id,
        '—'::text as doc_number,
        p_as_of as doc_at,
        c.id as cust_id,
        c.name as cust_name,
        nullif(trim(c.phone), '') as cust_phone,
        null::uuid as emp_id,
        '—'::text as emp_name,
        greatest(c.current_balance, 0)::numeric(14, 2) as doc_total,
        0::numeric(14, 2) as paid_total,
        (
          greatest(c.current_balance, 0)
          - coalesce(covered.covered, 0)
        )::numeric(14, 2) as open_amt,
        'Other outstanding'::text as doc_type,
        null::text as ref_number
      from public.customers c
      left join covered on covered.cust_id = c.id
      where not filter_reps
        and c.company_id = company
        and c.deleted_at is null
        and c.is_active = true
        and c.current_balance > 0.001
        and (
          greatest(c.current_balance, 0)
          - coalesce(covered.covered, 0)
        ) > 0.001
    )
    select *
    from (
      select * from line_rows
      union all
      select * from residual_rows
    ) report
    order by 5, 3, 2;
end;
$$;

comment on function public.fetch_collections_report(timestamptz, uuid[]) is
  'Open recognized AR and opening balances, capped to current_balance, plus '
  'Other outstanding for any leftover customer balance so All-reps total ties '
  'to Payments Outstanding.';

revoke all on function public.fetch_collections_report(timestamptz, uuid[])
  from public;
grant execute on function public.fetch_collections_report(timestamptz, uuid[])
  to authenticated;
