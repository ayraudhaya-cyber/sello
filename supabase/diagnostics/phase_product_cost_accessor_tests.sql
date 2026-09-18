-- Verification for migration 076 (product cost accessors, additive).
-- Role impersonation only; rolled back.
begin;

create table public._cost_accessor_results (
  seq serial primary key,
  test text,
  outcome text
);

grant all on public._cost_accessor_results to authenticated;
grant all on sequence public._cost_accessor_results_seq_seq to authenticated;

do $tests$
declare
  v_owner_user uuid := '99859a5f-a0eb-404f-8544-4d221dec805e';
  v_owner_emp  uuid := '02e2ec08-7251-4de0-82a4-e286520e30af';
  v_company    uuid := '0e5b1ff9-35d4-42bb-bc21-d374c1e86153';
  v_branch     uuid := '95696932-2421-4ed2-b492-18dd13093b9f';
  v_owner_role uuid;
  v_sales_role uuid;
  v_product    uuid;
  v_foreign    uuid;
  v_cost       numeric;
  v_value      numeric;
  v_expected   numeric;
  v_n          int;
begin
  select id into v_owner_role from public.roles where code = 'owner';
  select id into v_sales_role from public.roles where code = 'sales_representative';
  select id into v_product from public.products
   where company_id = v_company and deleted_at is null limit 1;
  select id into v_foreign from public.products
   where company_id <> v_company and deleted_at is null limit 1;

  -- Expected valuation computed directly, as the client used to do.
  select coalesce(sum(i.quantity * p.unit_cost), 0) into v_expected
  from public.inventory i
  join public.products p on p.id = i.product_id
  where i.company_id = v_company
    and p.deleted_at is null
    and p.is_active
    and i.branch_id = v_branch;

  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner_user::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('role', 'authenticated', true);

  begin
    execute 'select unit_cost from public.product_unit_costs(array[$1])'
      into v_cost using v_product;
    insert into public._cost_accessor_results (test, outcome)
    values ('T1 owner product_unit_costs()', 'OK ' || coalesce(v_cost::text, 'null'));
  exception when others then
    insert into public._cost_accessor_results (test, outcome)
    values ('T1 owner product_unit_costs()', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select public.inventory_stock_value($1)' into v_value using v_branch;
    insert into public._cost_accessor_results (test, outcome)
    values (
      'T2 owner inventory_stock_value() matches old client sum',
      case when v_value = v_expected then 'MATCH ' || v_value
           else 'MISMATCH got ' || v_value || ' expected ' || v_expected end
    );
  exception when others then
    insert into public._cost_accessor_results (test, outcome)
    values ('T2 owner inventory_stock_value()', 'FAILED ' || sqlerrm);
  end;

  if v_foreign is null then
    insert into public._cost_accessor_results (test, outcome)
    values ('T3 owner cross-tenant product cost', 'SKIPPED no other-tenant product');
  else
    begin
      execute 'select count(*) from public.product_unit_costs(array[$1])'
        into v_n using v_foreign;
      insert into public._cost_accessor_results (test, outcome)
      values ('T3 owner cross-tenant product cost', 'rows=' || v_n || ' (expected 0)');
    exception when others then
      insert into public._cost_accessor_results (test, outcome)
      values ('T3 owner cross-tenant product cost', 'FAILED ' || sqlerrm);
    end;
  end if;

  -- Sales Rep ------------------------------------------------------------------
  perform set_config('role', 'postgres', true);
  update public.employees set role_id = v_sales_role where id = v_owner_emp;
  perform set_config('role', 'authenticated', true);

  begin
    execute 'select count(*) from public.product_unit_costs(array[$1])'
      into v_n using v_product;
    insert into public._cost_accessor_results (test, outcome)
    values ('T4 sales product_unit_costs()', 'rows=' || v_n || ' (expected 0)');
  exception when others then
    insert into public._cost_accessor_results (test, outcome)
    values ('T4 sales product_unit_costs()', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select public.inventory_stock_value($1)' into v_value using v_branch;
    insert into public._cost_accessor_results (test, outcome)
    values ('T5 sales inventory_stock_value()', 'returned ' || v_value || ' (expected 0)');
  exception when others then
    insert into public._cost_accessor_results (test, outcome)
    values ('T5 sales inventory_stock_value()', 'FAILED ' || sqlerrm);
  end;

  -- 076 must not have changed any privilege: the current client still works.
  begin
    -- PostgREST compiles select=cost_price into the computed field call below.
    execute 'select count(*) from (select p.id, p.name, p.selling_price,
             public.cost_price(p) from public.products p limit 5) s' into v_n;
    insert into public._cost_accessor_results (test, outcome)
    values ('T6 current released client select (with cost_price)', 'OK rows=' || v_n);
  exception when others then
    insert into public._cost_accessor_results (test, outcome)
    values ('T6 current released client select (with cost_price)', 'FAILED ' || sqlerrm);
  end;

  begin
    execute 'select count(*) from (select id, name, sku, selling_price
             from public.products limit 5) s' into v_n;
    insert into public._cost_accessor_results (test, outcome)
    values ('T7 new client select (no cost_price)', 'OK rows=' || v_n);
  exception when others then
    insert into public._cost_accessor_results (test, outcome)
    values ('T7 new client select (no cost_price)', 'FAILED ' || sqlerrm);
  end;

  perform set_config('role', 'postgres', true);
  update public.employees set role_id = v_owner_role where id = v_owner_emp;
end
$tests$;

select test, outcome from public._cost_accessor_results order by seq;

rollback;
