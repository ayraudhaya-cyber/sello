-- =============================================================================
-- 075 — Hide product_variants.unit_cost from unauthorized API clients
--
-- Applies the principle of 059 (products.unit_cost) to the variant table:
-- cost stays physical on the row, clients cannot SELECT it, and only roles
-- passing can_view_product_cost() can read it through a tenant-scoped,
-- SECURITY DEFINER accessor.
--
-- Why this is not a verbatim copy of 059:
--
--   1. 070 granted table-level SELECT on product_variants to authenticated.
--      PostgreSQL ignores a column-level REVOKE while the table-level
--      privilege is held, so the column must be locked by revoking SELECT on
--      the table and re-granting it per column.
--
--   2. Once SELECT is column-level, a whole-row reference — which is what a
--      PostgREST computed field like cost_price(product_variants) compiles to
--      — requires SELECT on every column and is denied for everyone. So the
--      authorized read path is an explicit accessor rather than a computed
--      field. Verified against the linked project before writing this.
--
-- Not changed: RLS policies, INSERT/UPDATE privileges, pricing, SKU, barcode,
-- inventory, orders, and every other table.
-- =============================================================================

comment on column public.product_variants.unit_cost is
  'Variant cost. Not directly selectable by authenticated clients; exposed via '
  'variant_unit_costs() only for roles passing can_view_product_cost(). '
  'Writes (insert/update) are unaffected. Internal SECURITY DEFINER routines '
  'still read the column directly.';

-- ---------------------------------------------------------------------------
-- Column-level SELECT: every column except unit_cost
-- ---------------------------------------------------------------------------
--
-- Generated from the catalog so the grant matches the table as it exists when
-- this migration runs. MAINTENANCE CONTRACT: a later migration that adds a
-- column to product_variants must also grant SELECT on it to authenticated,
-- otherwise the column is invisible to the API.

do $$
declare
  v_columns text;
begin
  select string_agg(quote_ident(attname), ', ' order by attnum)
    into v_columns
  from pg_attribute
  where attrelid = 'public.product_variants'::regclass
    and attnum > 0
    and not attisdropped
    and attname <> 'unit_cost';

  if v_columns is null then
    raise exception 'product_variants has no selectable columns to grant';
  end if;

  execute 'revoke select on table public.product_variants from authenticated';
  execute format(
    'grant select (%s) on table public.product_variants to authenticated',
    v_columns
  );

  raise notice '075: granted SELECT on product_variants (%) to authenticated',
    v_columns;
end;
$$;

-- anon holds nothing on this table (070 revoked all); kept explicit so the
-- cost lock does not depend on an earlier migration staying unchanged.
revoke select on table public.product_variants from anon;

-- ---------------------------------------------------------------------------
-- Authorized read path
-- ---------------------------------------------------------------------------
--
-- Batch accessor so a Hub list can resolve costs in one call. Returns no rows
-- for roles that may not view cost, and never crosses the caller's company.

create or replace function public.variant_unit_costs(p_variant_ids uuid[])
returns table (variant_id uuid, unit_cost numeric)
language sql
stable
security definer
set search_path = public
as $$
  select v.id, v.unit_cost
  from public.product_variants v
  where v.id = any (coalesce(p_variant_ids, '{}'::uuid[]))
    and v.company_id = public.current_company_id()
    and v.deleted_at is null
    and public.can_view_product_cost();
$$;

comment on function public.variant_unit_costs(uuid[]) is
  'Variant cost for Owner/Manager/Store In-charge (can_view_product_cost). '
  'Company-scoped; returns no rows for other roles or other tenants. '
  'Mirrors the 059 masking principle for product_variants.unit_cost.';

revoke all on function public.variant_unit_costs(uuid[]) from public;
grant execute on function public.variant_unit_costs(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Verification — fails the migration if the lock is not exactly as intended
-- ---------------------------------------------------------------------------

do $$
declare
  v_leaked text;
  v_missing text;
begin
  if has_table_privilege('authenticated', 'public.product_variants', 'SELECT') then
    raise exception
      '075: authenticated still holds table-level SELECT; column lock is inert';
  end if;

  if has_column_privilege(
       'authenticated', 'public.product_variants', 'unit_cost', 'SELECT'
     ) then
    raise exception '075: authenticated can still SELECT product_variants.unit_cost';
  end if;

  select string_agg(attname, ', ' order by attnum)
    into v_missing
  from pg_attribute
  where attrelid = 'public.product_variants'::regclass
    and attnum > 0
    and not attisdropped
    and attname <> 'unit_cost'
    and not has_column_privilege(
      'authenticated', 'public.product_variants', attname, 'SELECT'
    );

  if v_missing is not null then
    raise exception '075: catalog columns lost SELECT for authenticated: %', v_missing;
  end if;

  -- Writes must be untouched: Hub still saves variant cost.
  if not has_column_privilege(
       'authenticated', 'public.product_variants', 'unit_cost', 'UPDATE'
     )
     or not has_column_privilege(
       'authenticated', 'public.product_variants', 'unit_cost', 'INSERT'
     ) then
    raise exception '075: write access to product_variants.unit_cost was lost';
  end if;

  select string_agg(privilege_type, ', ')
    into v_leaked
  from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name = 'product_variants'
    and grantee = 'anon';

  if v_leaked is not null then
    raise exception '075: anon unexpectedly holds % on product_variants', v_leaked;
  end if;

  if not has_function_privilege(
       'authenticated', 'public.variant_unit_costs(uuid[])', 'EXECUTE'
     ) then
    raise exception '075: authenticated cannot execute variant_unit_costs()';
  end if;

  raise notice '075: product_variants.unit_cost locked; authorized path verified';
end;
$$;
