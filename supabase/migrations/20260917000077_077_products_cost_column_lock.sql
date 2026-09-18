-- =============================================================================
-- 077 — Lock products.unit_cost (completes what 059 intended)
--
-- !! DO NOT APPLY UNTIL THE CLIENT BUILD THAT DROPS cost_price IS LIVE !!
--
-- 059 tried to hide products.unit_cost with a column-level REVOKE, but
-- authenticated holds table-level SELECT on products and PostgreSQL ignores a
-- column REVOKE while the table privilege is held. The column has therefore
-- been readable by every authenticated client, Sales Reps included, since 059.
-- Verified against the linked project: a Sales Rep session could read
-- products.unit_cost directly while cost_price() correctly returned null.
--
-- This migration does what 059 meant to do, using the mechanism proven in 075:
-- revoke SELECT on the table and re-grant it per column except unit_cost.
--
-- BREAKING FOR OLD CLIENTS. Column-level SELECT makes every whole-row
-- reference fail, and the cost_price(products) computed field compiles to one.
-- Any build still selecting cost_price will get "permission denied for table
-- products" on the product and inventory lists. 076 added product_unit_costs()
-- and inventory_stock_value() as replacements; ship the client that uses them
-- first, then apply this.
--
-- Not changed: RLS policies, INSERT/UPDATE privileges, anon grants (products
-- has no anon policy, so anon already reads nothing), pricing, or any other
-- table.
-- =============================================================================

comment on column public.products.unit_cost is
  'Internal unit cost for margin, valuation, and purchasing. Not selectable by '
  'API clients; exposed via product_unit_costs() and inventory_stock_value() '
  'only for roles passing can_view_product_cost(). Writes are unaffected, and '
  'internal SECURITY DEFINER routines still read the column directly.';

-- ---------------------------------------------------------------------------
-- Column-level SELECT: every column except unit_cost
-- ---------------------------------------------------------------------------
--
-- MAINTENANCE CONTRACT: a later migration that adds a column to products must
-- also grant SELECT on it to authenticated, or the column is invisible to the
-- API.

do $$
declare
  v_columns text;
begin
  select string_agg(quote_ident(attname), ', ' order by attnum)
    into v_columns
  from pg_attribute
  where attrelid = 'public.products'::regclass
    and attnum > 0
    and not attisdropped
    and attname <> 'unit_cost';

  if v_columns is null then
    raise exception 'products has no selectable columns to grant';
  end if;

  execute 'revoke select on table public.products from authenticated';
  execute format(
    'grant select (%s) on table public.products to authenticated',
    v_columns
  );

  raise notice '077: granted SELECT on products (%) to authenticated', v_columns;
end;
$$;

-- ---------------------------------------------------------------------------
-- Retire the computed field
-- ---------------------------------------------------------------------------
--
-- cost_price(products) cannot work once SELECT is column-level: PostgREST
-- passes the whole row, which requires SELECT on every column. Dropping it
-- turns a confusing "permission denied for table products" into a clear
-- "column cost_price does not exist" for anything still asking for it.

drop function if exists public.cost_price(public.products);

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

do $$
declare
  v_missing text;
begin
  if has_table_privilege('authenticated', 'public.products', 'SELECT') then
    raise exception
      '077: authenticated still holds table-level SELECT; column lock is inert';
  end if;

  if has_column_privilege('authenticated', 'public.products', 'unit_cost', 'SELECT')
  then
    raise exception '077: authenticated can still SELECT products.unit_cost';
  end if;

  select string_agg(attname, ', ' order by attnum)
    into v_missing
  from pg_attribute
  where attrelid = 'public.products'::regclass
    and attnum > 0
    and not attisdropped
    and attname <> 'unit_cost'
    and not has_column_privilege(
      'authenticated', 'public.products', attname, 'SELECT'
    );

  if v_missing is not null then
    raise exception '077: catalog columns lost SELECT for authenticated: %', v_missing;
  end if;

  if not has_column_privilege('authenticated', 'public.products', 'unit_cost', 'UPDATE')
     or not has_column_privilege(
       'authenticated', 'public.products', 'unit_cost', 'INSERT'
     ) then
    raise exception '077: write access to products.unit_cost was lost';
  end if;

  if not has_function_privilege(
       'authenticated', 'public.product_unit_costs(uuid[])', 'EXECUTE'
     ) then
    raise exception '077: product_unit_costs() is missing; apply 076 first';
  end if;

  raise notice '077: products.unit_cost locked; authorized path verified';
end;
$$;
