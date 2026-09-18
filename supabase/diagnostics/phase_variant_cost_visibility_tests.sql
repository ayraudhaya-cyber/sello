-- Verification for migration 075 (product_variants.unit_cost visibility).
-- Role impersonation only; all writes are rolled back.
begin;

create table public._cost_visibility_results (
  seq serial primary key,
  test text,
  outcome text
);

grant all on public._cost_visibility_results to authenticated;
grant all on sequence public._cost_visibility_results_seq_seq to authenticated;

do $tests$
declare
  v_owner_user uuid := '99859a5f-a0eb-404f-8544-4d221dec805e';
  v_owner_emp  uuid := '02e2ec08-7251-4de0-82a4-e286520e30af';
  v_company    uuid := '0e5b1ff9-35d4-42bb-bc21-d374c1e86153';
  v_owner_role uuid;
  v_sales_role uuid;
  v_cost       numeric;
  v_n          int;
  v_variant    uuid;
  v_foreign    uuid;
begin
  select id into v_owner_role from public.roles where code = 'owner';
  select id into v_sales_role from public.roles where code = 'sales_representative';
  select id into v_variant from public.product_variants
   where company_id = v_company and deleted_at is null limit 1;
  select id into v_foreign from public.product_variants
   where company_id <> v_company and deleted_at is null limit 1;

  -- Static privilege state ----------------------------------------------------
  insert into public._cost_visibility_results (test, outcome)
  values (
    'P1 authenticated table-level SELECT',
    has_table_privilege('authenticated', 'public.product_variants', 'SELECT')::text
      || ' (expected false)'
  ), (
    'P2 authenticated SELECT unit_cost',
    has_column_privilege(
      'authenticated', 'public.product_variants', 'unit_cost', 'SELECT'
    )::text || ' (expected false)'
  ), (
    'P3 authenticated SELECT selling_price',
    has_column_privilege(
      'authenticated', 'public.product_variants', 'selling_price', 'SELECT'
    )::text || ' (expected true)'
  ), (
    'P4 authenticated UPDATE unit_cost',
    has_column_privilege(
      'authenticated', 'public.product_variants', 'unit_cost', 'UPDATE'
    )::text || ' (expected true)'
  ), (
    'P5 anon privileges on product_variants',
    coalesce(
      (select string_agg(privilege_type, ',')
         from information_schema.role_table_grants
        where table_schema = 'public' and table_name = 'product_variants'
          and grantee = 'anon'),
      'none'
    )
  ), (
    'P6 products grants unchanged',
    coalesce(
      (select string_agg(privilege_type, ',' order by privilege_type)
         from information_schema.role_table_grants
        where table_schema = 'public' and table_name = 'products'
          and grantee = 'authenticated'),
      'none'
    )
  );

  -- Owner behaviour -----------------------------------------------------------
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner_user::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('role', 'authenticated', true);

  begin
    execute 'select count(*) from (select id, sku, barcode, selling_price,
             is_default, is_active from public.product_variants limit 10) s' into v_n;
    insert into public._cost_visibility_results (test, outcome)
    values ('T1 owner catalog read (Flutter column set)', 'OK rows=' || v_n);
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T1 owner catalog read (Flutter column set)', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select count(*) from (
               select p.id, v.id, v.sku, v.selling_price
               from public.products p
               join public.product_variants v on v.product_id = p.id
               limit 10) s' into v_n;
    insert into public._cost_visibility_results (test, outcome)
    values ('T2 owner product + variant embed shape', 'OK rows=' || v_n);
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T2 owner product + variant embed shape', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select count(*) from (
               select i.id, v.id, v.label, v.sku
               from public.inventory i
               join public.product_variants v on v.id = i.variant_id
               limit 10) s' into v_n;
    insert into public._cost_visibility_results (test, outcome)
    values ('T3 owner inventory + variant embed shape', 'OK rows=' || v_n);
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T3 owner inventory + variant embed shape', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select unit_cost from public.product_variants limit 1' into v_cost;
    insert into public._cost_visibility_results (test, outcome)
    values ('T4 owner raw unit_cost', 'READABLE ' || coalesce(v_cost::text, 'null'));
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T4 owner raw unit_cost', 'BLOCKED ' || sqlerrm);
  end;

  begin
    execute 'select unit_cost from public.variant_unit_costs(array[$1])'
      into v_cost using v_variant;
    insert into public._cost_visibility_results (test, outcome)
    values (
      'T5 owner variant_unit_costs() authorized path',
      'OK ' || coalesce(v_cost::text, 'null')
    );
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T5 owner variant_unit_costs() authorized path', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'update public.product_variants
                set unit_cost = 12.34, selling_price = 99, updated_by = $2
              where id = $1' using v_variant, v_owner_emp;
    insert into public._cost_visibility_results (test, outcome)
    values ('T6 owner saves variant cost (Hub write path)', 'OK');
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T6 owner saves variant cost (Hub write path)', 'FAILED ' || sqlerrm);
  end;

  if v_foreign is null then
    insert into public._cost_visibility_results (test, outcome)
    values ('T7 owner cross-tenant cost', 'SKIPPED no other-tenant variant');
  else
    begin
      execute 'select count(*) from public.variant_unit_costs(array[$1])'
        into v_n using v_foreign;
      insert into public._cost_visibility_results (test, outcome)
      values ('T7 owner cross-tenant cost', 'rows=' || v_n || ' (expected 0)');
    exception when others then
      insert into public._cost_visibility_results (test, outcome)
      values ('T7 owner cross-tenant cost', 'FAILED ' || sqlerrm);
    end;
  end if;

  -- Sales Rep behaviour -------------------------------------------------------
  perform set_config('role', 'postgres', true);
  update public.employees set role_id = v_sales_role where id = v_owner_emp;
  perform set_config('role', 'authenticated', true);

  begin
    execute 'select count(*) from (select id, sku, selling_price
             from public.product_variants limit 10) s' into v_n;
    insert into public._cost_visibility_results (test, outcome)
    values ('T8 sales catalog read', 'OK rows=' || v_n);
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T8 sales catalog read', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select unit_cost from public.product_variants limit 1' into v_cost;
    insert into public._cost_visibility_results (test, outcome)
    values ('T9 sales raw unit_cost', 'READABLE ' || coalesce(v_cost::text, 'null'));
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T9 sales raw unit_cost', 'BLOCKED ' || sqlerrm);
  end;

  begin
    execute 'select count(*) from public.variant_unit_costs(array[$1])'
      into v_n using v_variant;
    insert into public._cost_visibility_results (test, outcome)
    values ('T10 sales variant_unit_costs()', 'rows=' || v_n || ' (expected 0)');
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T10 sales variant_unit_costs()', 'FAILED ' || sqlerrm);
  end;

  -- Internal SECURITY DEFINER paths must still see cost ------------------------
  perform set_config('role', 'postgres', true);
  update public.employees set role_id = v_owner_role where id = v_owner_emp;

  begin
    select count(*) into v_n
    from public.product_variants where unit_cost >= 0;
    insert into public._cost_visibility_results (test, outcome)
    values ('T11 internal/definer read of unit_cost', 'OK rows=' || v_n);
  exception when others then
    insert into public._cost_visibility_results (test, outcome)
    values ('T11 internal/definer read of unit_cost', 'FAILED ' || sqlerrm);
  end;
end
$tests$;

select test, outcome from public._cost_visibility_results order by seq;

rollback;
