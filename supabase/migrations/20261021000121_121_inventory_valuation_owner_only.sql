-- =============================================================================
-- 121 — Inventory worth at cost / selling: Owner only
--
-- Stock valuation KPIs must not leak to Manager or other Hub roles. Product
-- unit cost visibility (can_view_product_cost) is unchanged.
-- =============================================================================

create or replace function public.can_view_inventory_valuation()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role_code(), '') = 'owner';
$$;

comment on function public.can_view_inventory_valuation() is
  'True only for Owner — inventory worth at cost and worth at selling.';

revoke all on function public.can_view_inventory_valuation() from public;
grant execute on function public.can_view_inventory_valuation() to authenticated;

create or replace function public.inventory_stock_value(p_branch_id uuid default null)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.can_view_inventory_valuation() then 0
    else coalesce(
      (
        select sum(i.quantity * p.unit_cost)
        from public.inventory i
        join public.products p on p.id = i.product_id
        where i.company_id = public.current_company_id()
          and p.deleted_at is null
          and p.is_active
          and (p_branch_id is null or i.branch_id = p_branch_id)
      ),
      0
    )
  end;
$$;

comment on function public.inventory_stock_value(uuid) is
  'Branch (or company-wide) stock valuation at cost. Owner only via '
  'can_view_inventory_valuation(); returns 0 for every other role.';

create or replace function public.inventory_stock_selling_value(
  p_branch_id uuid default null
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.can_view_inventory_valuation() then 0
    else coalesce(
      (
        select sum(i.quantity * coalesce(v.selling_price, 0))
        from public.inventory i
        join public.products p on p.id = i.product_id
        join public.product_variants v on v.id = i.variant_id
        where i.company_id = public.current_company_id()
          and p.deleted_at is null
          and p.is_active
          and (p_branch_id is null or i.branch_id = p_branch_id)
      ),
      0
    )
  end;
$$;

comment on function public.inventory_stock_selling_value(uuid) is
  'On-hand × variant selling price. Owner only via can_view_inventory_valuation().';
