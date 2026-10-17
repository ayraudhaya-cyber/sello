-- Read-only diagnosis for Namson Lanka customer balances.
-- Run the whole file in Supabase SQL Editor and share both result grids.

with target_company as (
  select id
  from public.companies
  where lower(name) like '%namson%'
    and lower(name) like '%lanka%'
  limit 1
),
adjustments as (
  select
    a.customer_id,
    sum(a.amount) filter (where a.reversed_at is null) as active_opening_docs,
    count(*) filter (where a.reversed_at is null) as opening_doc_count
  from public.customer_receivable_adjustments a
  join target_company tc on tc.id = a.company_id
  group by a.customer_id
),
orders as (
  select
    o.customer_id,
    sum(coalesce(o.recognized_receivable_value, 0)) as recognized_order_ar,
    sum(o.total) filter (
      where o.status in ('placed', 'partially_delivered', 'completed')
    ) as active_order_total,
    count(*) filter (
      where o.status in ('placed', 'partially_delivered', 'completed')
    ) as active_order_count
  from public.orders o
  join target_company tc on tc.id = o.company_id
  where o.deleted_at is null
  group by o.customer_id
),
payment_allocations as (
  select
    p.id as payment_id,
    coalesce(sum(pa.amount), 0) as allocated
  from public.payments p
  join target_company tc on tc.id = p.company_id
  left join public.payment_allocations pa on pa.payment_id = p.id
  where p.deleted_at is null
    and p.status = 'completed'
  group by p.id
),
payments as (
  select
    p.customer_id,
    sum(p.amount) filter (where p.method <> 'wallet') as money_received,
    sum(p.amount) filter (where p.method = 'wallet') as wallet_spent,
    sum(greatest(p.amount - coalesce(pa.allocated, 0), 0))
      filter (where p.method <> 'wallet') as unallocated_received,
    count(*) filter (where p.method <> 'wallet') as collection_count
  from public.payments p
  join target_company tc on tc.id = p.company_id
  left join payment_allocations pa on pa.payment_id = p.id
  where p.deleted_at is null
    and p.status = 'completed'
  group by p.customer_id
)
select
  c.name as customer,
  c.opening_balance as stored_opening,
  coalesce(a.active_opening_docs, 0) as opening_documents,
  coalesce(o.recognized_order_ar, 0) as recognized_order_ar,
  coalesce(o.active_order_total, 0) as active_order_total,
  coalesce(p.money_received, 0) as money_received,
  coalesce(p.unallocated_received, 0) as unallocated_received,
  coalesce(p.wallet_spent, 0) as wallet_spent,
  c.current_balance as stored_outstanding,
  c.wallet_balance as stored_wallet,
  coalesce(a.opening_doc_count, 0) as opening_docs,
  coalesce(o.active_order_count, 0) as active_orders,
  coalesce(p.collection_count, 0) as collections
from public.customers c
join target_company tc on tc.id = c.company_id
left join adjustments a on a.customer_id = c.id
left join orders o on o.customer_id = c.id
left join payments p on p.customer_id = c.id
where c.deleted_at is null
order by c.name;

-- Exact source rows for SS GLASS POINT.
with target_customer as (
  select c.id
  from public.customers c
  join public.companies co on co.id = c.company_id
  where lower(co.name) like '%namson%'
    and lower(co.name) like '%lanka%'
    and lower(c.name) = 'ss glass point'
  limit 1
)
select *
from (
  select
    'OPENING'::text as source,
    a.adjustment_number as reference,
    a.recognized_at as occurred_at,
    a.amount,
    a.reversed_at is null as active,
    coalesce(a.notes, '') as detail
  from public.customer_receivable_adjustments a
  join target_customer tc on tc.id = a.customer_id

  union all

  select
    'ORDER',
    o.order_number,
    o.ordered_at,
    o.total,
    o.deleted_at is null and o.status <> 'cancelled',
    'status=' || o.status
      || ', recognized_ar='
      || coalesce(o.recognized_receivable_value, 0)::text
  from public.orders o
  join target_customer tc on tc.id = o.customer_id

  union all

  select
    'PAYMENT',
    p.payment_number,
    p.received_at,
    p.amount,
    p.deleted_at is null and p.status = 'completed',
    'method=' || p.method
      || ', status=' || p.status
      || ', allocated=' || coalesce(sum(pa.amount), 0)::text
      || ', applied_ar=' || coalesce(p.applied_ar_amount, 0)::text
      || ', applied_wallet=' || coalesce(p.applied_wallet_amount, 0)::text
  from public.payments p
  join target_customer tc on tc.id = p.customer_id
  left join public.payment_allocations pa on pa.payment_id = p.id
  group by
    p.id,
    p.payment_number,
    p.received_at,
    p.amount,
    p.deleted_at,
    p.status,
    p.method,
    p.applied_ar_amount,
    p.applied_wallet_amount
) ledger
order by occurred_at, source, reference;
