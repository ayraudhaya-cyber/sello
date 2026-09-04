-- =============================================================================
-- 059 — Hide products.unit_cost from Sales Rep API responses
--
-- Physical cost stays on products.unit_cost (was cost_price). Authenticated
-- clients cannot SELECT it. PostgREST exposes a computed cost_price(products)
-- that returns the real value only for Owner/Manager; Sales gets NULL.
-- Writes use unit_cost. Internal RPCs / SECURITY DEFINER still read unit_cost.
-- =============================================================================

alter table public.products
  rename column cost_price to unit_cost;

comment on column public.products.unit_cost is
  'Internal unit cost for margin, valuation, and purchasing. '
  'Not directly selectable by authenticated clients; exposed via cost_price() '
  'only for Owner/Manager.';

-- Column-level lock: Sales (and any authenticated client) cannot read raw cost.
revoke select (unit_cost) on table public.products from authenticated;
revoke select (unit_cost) on table public.products from anon;

-- Keep write access so Hub product upserts can set cost.
grant insert (unit_cost) on table public.products to authenticated;
grant update (unit_cost) on table public.products to authenticated;

create or replace function public.can_view_product_cost()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_role_code() in ('owner', 'manager');
$$;

revoke all on function public.can_view_product_cost() from public;
grant execute on function public.can_view_product_cost() to authenticated;

-- Computed field: select=cost_price resolves here; unnamed arg avoids /rpc exposure.
create or replace function public.cost_price(public.products)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.can_view_product_cost() then $1.unit_cost
    else null
  end;
$$;

revoke all on function public.cost_price(public.products) from public;
grant execute on function public.cost_price(public.products) to authenticated;
