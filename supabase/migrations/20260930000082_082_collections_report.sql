-- =============================================================================
-- 082 — Collections Report (as-of open invoices by sales rep)
--
-- Historical snapshot: order total minus completed allocations received on or
-- before p_as_of. Pending collections and later payments do not reduce the
-- balance. Matches Hub receivable eligibility (placed / partially_delivered /
-- completed, not archived).
-- =============================================================================

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
  open_balance numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
begin
  if company is null then
    raise exception 'Session context missing.';
  end if;

  return query
  with paid as (
    select
      pa.order_id,
      coalesce(sum(pa.amount), 0)::numeric(14, 2) as amount_paid
    from public.payment_allocations pa
    inner join public.payments p on p.id = pa.payment_id
    where p.company_id = company
      and p.status = 'completed'
      and p.deleted_at is null
      and p.received_at <= p_as_of
    group by pa.order_id
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
    coalesce(paid.amount_paid, 0)::numeric(14, 2),
    (o.total - coalesce(paid.amount_paid, 0))::numeric(14, 2)
  from public.orders o
  inner join public.customers c on c.id = o.customer_id
  left join public.employees e on e.id = o.employee_id
  left join paid on paid.order_id = o.id
  where o.company_id = company
    and o.deleted_at is null
    and o.status in ('placed', 'partially_delivered', 'completed')
    and o.ordered_at <= p_as_of
    and (
      p_employee_ids is null
      or cardinality(p_employee_ids) = 0
      or o.employee_id = any (p_employee_ids)
    )
    and (o.total - coalesce(paid.amount_paid, 0)) > 0.001
  order by lower(c.name), o.ordered_at, o.order_number;
end;
$$;

comment on function public.fetch_collections_report(timestamptz, uuid[]) is
  'As-of open invoices for the Collections Report. Open balance = order total minus completed allocations received on or before p_as_of.';

revoke all on function public.fetch_collections_report(timestamptz, uuid[])
  from public;
grant execute on function public.fetch_collections_report(timestamptz, uuid[])
  to authenticated;
