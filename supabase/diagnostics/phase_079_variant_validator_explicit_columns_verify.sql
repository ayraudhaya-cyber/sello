-- =============================================================================
-- Post-079 verification (run AFTER applying 079 in the target environment)
--
-- Safe: privilege introspection + optional rollback-wrapped probes.
-- Does NOT weaken grants/RLS. Roll back any DML probes at the end.
-- =============================================================================

begin;

create temporary table _079_verify (
  seq serial primary key,
  check_name text not null,
  outcome text not null
);

-- ---------------------------------------------------------------------------
-- Static privilege / security posture
-- ---------------------------------------------------------------------------
insert into _079_verify (check_name, outcome)
values
  (
    'authenticated table-level SELECT on product_variants',
    has_table_privilege('authenticated', 'public.product_variants', 'SELECT')::text
      || ' (expected false)'
  ),
  (
    'authenticated SELECT product_variants.unit_cost',
    has_column_privilege(
      'authenticated', 'public.product_variants', 'unit_cost', 'SELECT'
    )::text || ' (expected false)'
  ),
  (
    'authenticated INSERT product_variants',
    has_table_privilege('authenticated', 'public.product_variants', 'INSERT')::text
      || ' (expected true)'
  ),
  (
    'authenticated UPDATE product_variants',
    has_table_privilege('authenticated', 'public.product_variants', 'UPDATE')::text
      || ' (expected true)'
  ),
  (
    'authenticated DELETE product_variants',
    has_table_privilege('authenticated', 'public.product_variants', 'DELETE')::text
      || ' (expected false)'
  ),
  (
    'validate_inventory_tenant_scope is SECURITY DEFINER',
    (
      select p.prosecdef::text
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'validate_inventory_tenant_scope'
    ) || ' (expected false = INVOKER)'
  ),
  (
    'validate_stock_movement_tenant_scope is SECURITY DEFINER',
    (
      select p.prosecdef::text
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'validate_stock_movement_tenant_scope'
    ) || ' (expected false = INVOKER)'
  ),
  (
    'RLS enabled on product_variants',
    (
      select c.relrowsecurity::text
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'product_variants'
    ) || ' (expected true)'
  ),
  (
    'product_variants policies still present',
    (
      select count(*)::text
      from pg_policies
      where schemaname = 'public'
        and tablename = 'product_variants'
    ) || ' (expected 3: select/insert/update)'
  ),
  (
    'anon grants on product_variants',
    coalesce(
      (
        select string_agg(privilege_type, ',' order by privilege_type)
        from information_schema.role_table_grants
        where table_schema = 'public'
          and table_name = 'product_variants'
          and grantee = 'anon'
      ),
      'none'
    ) || ' (expected none)'
  );

-- ---------------------------------------------------------------------------
-- Function source must not contain whole-row product_variants reads
-- ---------------------------------------------------------------------------
insert into _079_verify (check_name, outcome)
select
  'inventory validator avoids SELECT * / %rowtype',
  case
    when pg_get_functiondef(p.oid) ~* 'product_variants%rowtype'
      or pg_get_functiondef(p.oid) ~* 'select\s+\*\s+into'
    then 'FAILED still has whole-row read'
    else 'OK'
  end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'validate_inventory_tenant_scope';

insert into _079_verify (check_name, outcome)
select
  'stock_movement validator avoids SELECT * / %rowtype',
  case
    when pg_get_functiondef(p.oid) ~* 'product_variants%rowtype'
      or pg_get_functiondef(p.oid) ~* 'select\s+\*\s+into'
    then 'FAILED still has whole-row read'
    else 'OK'
  end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'validate_stock_movement_tenant_scope';

select seq, check_name, outcome
from _079_verify
order by seq;

-- Manual authenticated probes (optional; fill IDs for your tenant):
--   set local role authenticated;
--   set request.jwt.claims = '{"sub":"<auth_user_uuid>","role":"authenticated"}';
--   -- expect fail:
--   select unit_cost from public.product_variants limit 1;
--   -- expect succeed (explicit columns):
--   select id, company_id, product_id, is_default from public.product_variants limit 1;
--   -- inventory upsert with valid company/branch/variant should no longer
--   -- raise "permission denied for table product_variants".

rollback;
