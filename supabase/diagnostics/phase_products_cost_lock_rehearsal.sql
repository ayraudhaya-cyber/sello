-- Rehearsal for migration 077 (products.unit_cost lock). Always rolled back.
-- Proves the lock applies cleanly and that the post-077 client shapes work.
begin;

create table public._lock_rehearsal_results (
  seq serial primary key,
  test text,
  outcome text
);

grant all on public._lock_rehearsal_results to authenticated;
grant all on sequence public._lock_rehearsal_results_seq_seq to authenticated;

do $rehearsal$
declare
  v_owner_user uuid := '99859a5f-a0eb-404f-8544-4d221dec805e';
  v_owner_emp  uuid := '02e2ec08-7251-4de0-82a4-e286520e30af';
  v_company    uuid := '0e5b1ff9-35d4-42bb-bc21-d374c1e86153';
  v_branch     uuid := '95696932-2421-4ed2-b492-18dd13093b9f';
  v_owner_role uuid;
  v_sales_role uuid;
  v_product    uuid;
  v_columns    text;
  v_cost       numeric;
  v_value      numeric;
  v_n          int;
begin
  select id into v_owner_role from public.roles where code = 'owner';
  select id into v_sales_role from public.roles where code = 'sales_representative';
  select id into v_product from public.products
   where company_id = v_company and deleted_at is null limit 1;

  -- 077 body -------------------------------------------------------------------
  select string_agg(quote_ident(attname), ', ' order by attnum)
    into v_columns
  from pg_attribute
  where attrelid = 'public.products'::regclass
    and attnum > 0
    and not attisdropped
    and attname <> 'unit_cost';

  execute 'revoke select on table public.products from authenticated';
  execute format('grant select (%s) on table public.products to authenticated', v_columns);
  execute 'drop function if exists public.cost_price(public.products)';

  insert into public._lock_rehearsal_results (test, outcome)
  values (
    'P1 authenticated table-level SELECT on products',
    has_table_privilege('authenticated', 'public.products', 'SELECT')::text
      || ' (expected false)'
  ), (
    'P2 authenticated SELECT products.unit_cost',
    has_column_privilege('authenticated', 'public.products', 'unit_cost', 'SELECT')::text
      || ' (expected false)'
  ), (
    'P3 authenticated UPDATE products.unit_cost',
    has_column_privilege('authenticated', 'public.products', 'unit_cost', 'UPDATE')::text
      || ' (expected true)'
  );

  -- Owner ----------------------------------------------------------------------
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner_user::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('role', 'authenticated', true);

  begin
    execute 'select count(*) from (
               select id, company_id, category_id, sku, barcode, name, brand,
                      description, unit_label, selling_price,
                      preferred_supplier_id, is_active, attributes,
                      created_at, updated_at
               from public.products limit 5) s' into v_n;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T1 owner post-077 catalog select', 'OK rows=' || v_n);
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T1 owner post-077 catalog select', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select count(*) from (
               select i.id, p.name, p.sku
               from public.inventory i
               join public.products p on p.id = i.product_id
               limit 5) s' into v_n;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T2 owner inventory + product embed', 'OK rows=' || v_n);
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T2 owner inventory + product embed', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select unit_cost from public.products limit 1' into v_cost;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T3 owner raw products.unit_cost', 'READABLE ' || coalesce(v_cost::text, 'null'));
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T3 owner raw products.unit_cost', 'BLOCKED ' || sqlerrm);
  end;

  begin
    execute 'select unit_cost from public.product_unit_costs(array[$1])'
      into v_cost using v_product;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T4 owner product_unit_costs()', 'OK ' || coalesce(v_cost::text, 'null'));
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T4 owner product_unit_costs()', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select public.inventory_stock_value($1)' into v_value using v_branch;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T5 owner inventory_stock_value()', 'OK ' || v_value);
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T5 owner inventory_stock_value()', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'update public.products
                set unit_cost = 5.5, selling_price = 10, updated_by = $2
              where id = $1' using v_product, v_owner_emp;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T6 owner saves product cost (Hub write path)', 'OK');
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T6 owner saves product cost (Hub write path)', 'FAILED ' || sqlerrm);
  end;

  -- Sales Rep --------------------------------------------------------------------
  perform set_config('role', 'postgres', true);
  update public.employees set role_id = v_sales_role where id = v_owner_emp;
  perform set_config('role', 'authenticated', true);

  begin
    execute 'select count(*) from (select id, name, sku, selling_price
             from public.products limit 5) s' into v_n;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T7 sales post-077 catalog select', 'OK rows=' || v_n);
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T7 sales post-077 catalog select', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select unit_cost from public.products limit 1' into v_cost;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T8 sales raw products.unit_cost', 'READABLE ' || coalesce(v_cost::text, 'null'));
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T8 sales raw products.unit_cost', 'BLOCKED ' || sqlerrm);
  end;

  begin
    execute 'select count(*) from public.product_unit_costs(array[$1])'
      into v_n using v_product;
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T9 sales product_unit_costs()', 'rows=' || v_n || ' (expected 0)');
  exception when others then
    insert into public._lock_rehearsal_results (test, outcome)
    values ('T9 sales product_unit_costs()', 'FAILED ' || sqlerrm);
  end;

  perform set_config('role', 'postgres', true);
  update public.employees set role_id = v_owner_role where id = v_owner_emp;
end
$rehearsal$;

select test, outcome from public._lock_rehearsal_results order by seq;

rollback;
