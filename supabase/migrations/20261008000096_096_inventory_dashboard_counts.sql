-- 096 — Inventory dashboard counts in one round trip.
--
-- The Hub dashboard, Reports overview, and Sales Home used to download every
-- inventory row just to count low / out-of-stock items. This function returns
-- the same tallies from the database.
--
-- SECURITY INVOKER: callers see exactly the rows RLS already allows on
-- `inventory`, `products`, and `stock_movements` (no visibility change).

create or replace function public.inventory_dashboard_counts(
  p_branch_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with active_stock as (
    select i.quantity, i.reorder_level, i.updated_at
    from public.inventory i
    join public.products p on p.id = i.product_id
    where p.deleted_at is null
      and coalesce(p.is_active, true)
      and (p_branch_id is null or i.branch_id = p_branch_id)
  )
  select jsonb_build_object(
    'total_items', (select count(*) from active_stock),
    'low_stock', (
      select count(*) from active_stock
      where quantity > 0
        and reorder_level is not null
        and quantity <= reorder_level
    ),
    'out_of_stock', (select count(*) from active_stock where quantity <= 0),
    'negative_stock', (select count(*) from active_stock where quantity < 0),
    'recently_updated', (
      select count(*) from active_stock
      where updated_at > timezone('utc', now()) - interval '7 days'
    ),
    'recent_movements', (
      select count(*)
      from public.stock_movements m
      where m.created_at > timezone('utc', now()) - interval '7 days'
        and (p_branch_id is null or m.branch_id = p_branch_id)
    )
  );
$$;

comment on function public.inventory_dashboard_counts(uuid) is
  'Dashboard tallies (total, low, out, negative, recently updated, 7-day movements). RLS-scoped (security invoker).';

revoke all on function public.inventory_dashboard_counts(uuid) from public;
grant execute on function public.inventory_dashboard_counts(uuid) to authenticated;
