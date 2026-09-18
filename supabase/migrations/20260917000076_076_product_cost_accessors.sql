-- =============================================================================
-- 076 — Authorized read paths for product cost (additive; nothing is locked yet)
--
-- Step 1 of closing the products.unit_cost exposure the same way 075 closed it
-- for product_variants. This migration only ADDS accessors so the Flutter
-- client can stop selecting the cost_price() computed field. The column lock
-- itself lands in a follow-up migration once the updated build is live.
--
-- Why the split: locking SELECT to column level makes every whole-row
-- reference fail, and a PostgREST computed field such as cost_price(products)
-- compiles to exactly that. Any client still asking for cost_price would break.
-- Applying the lock before clients are updated would take down the product and
-- inventory lists for everyone.
--
-- Authorization reuses can_view_product_cost() (Owner, Manager, Store
-- In-charge). Both functions are company-scoped and never cross tenants.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Per-product cost for a page of products
-- ---------------------------------------------------------------------------

create or replace function public.product_unit_costs(p_product_ids uuid[])
returns table (product_id uuid, unit_cost numeric)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.unit_cost
  from public.products p
  where p.id = any (coalesce(p_product_ids, '{}'::uuid[]))
    and p.company_id = public.current_company_id()
    and p.deleted_at is null
    and public.can_view_product_cost();
$$;

comment on function public.product_unit_costs(uuid[]) is
  'Product cost for Owner/Manager/Store In-charge (can_view_product_cost). '
  'Company-scoped; returns no rows for other roles or other tenants. '
  'Replaces client selects of the cost_price(products) computed field.';

revoke all on function public.product_unit_costs(uuid[]) from public;
grant execute on function public.product_unit_costs(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Branch stock valuation
-- ---------------------------------------------------------------------------
--
-- Server-side equivalent of the client-side sum the Inventory dashboard used
-- to compute from cost_price: on-hand quantity x parent product cost, over
-- active, non-deleted products. Raw quantity is intentional — negative stock
-- reduces valuation exactly as it did before. Returns 0 for roles that may not
-- view cost, matching the previous behaviour where cost_price came back null.

create or replace function public.inventory_stock_value(p_branch_id uuid default null)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.can_view_product_cost() then 0
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
  'Branch (or company-wide when null) stock valuation using products.unit_cost. '
  'Gated by can_view_product_cost(); returns 0 for roles that may not view cost. '
  'Valuation stays on the parent product cost — variants mirror it in V1.';

revoke all on function public.inventory_stock_value(uuid) from public;
grant execute on function public.inventory_stock_value(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

do $$
begin
  if not has_function_privilege(
       'authenticated', 'public.product_unit_costs(uuid[])', 'EXECUTE'
     ) then
    raise exception '076: authenticated cannot execute product_unit_costs()';
  end if;

  if not has_function_privilege(
       'authenticated', 'public.inventory_stock_value(uuid)', 'EXECUTE'
     ) then
    raise exception '076: authenticated cannot execute inventory_stock_value()';
  end if;

  -- This migration must not change any table privilege.
  if not has_table_privilege('authenticated', 'public.products', 'SELECT') then
    raise exception '076: products SELECT changed; this migration is additive only';
  end if;

  raise notice '076: product cost accessors created (no privileges changed)';
end;
$$;
