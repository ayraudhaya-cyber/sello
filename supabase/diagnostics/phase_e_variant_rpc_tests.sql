begin;

create temporary table if not exists _phase_e_results (
  test_id text primary key,
  status text not null,
  detail text
) on commit drop;

do $tests$
declare
  v_user uuid := '99859a5f-a0eb-404f-8544-4d221dec805e';
  v_emp uuid := '02e2ec08-7251-4de0-82a4-e286520e30af';
  v_company uuid := '0e5b1ff9-35d4-42bb-bc21-d374c1e86153';
  v_branch uuid := '95696932-2421-4ed2-b492-18dd13093b9f';
  v_existing_product uuid := '9188f7c5-77b6-44b6-8ee1-ae11d3acbc19';
  v_existing_variant uuid := 'fdcad508-fe09-4849-984c-d82958a0d9ab';
  v_existing_qty_before numeric;
  v_existing_qty_after numeric;
  v_product uuid;
  v_var_a uuid;
  v_var_b uuid;
  v_inv_a public.inventory%rowtype;
  v_inv_b public.inventory%rowtype;
  v_customer uuid;
  v_order uuid;
  v_item uuid;
  v_allow_above boolean;
  v_allow_neg boolean;
  v_err text;
  v_hist_mov_variant uuid;
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', v_user::text, true);

  if public.current_company_id() is distinct from v_company then
    insert into _phase_e_results values ('setup', 'FAIL', 'impersonation failed');
    return;
  end if;

  select quantity into v_existing_qty_before
  from public.inventory
  where variant_id = v_existing_variant and branch_id = v_branch;

  select variant_id into v_hist_mov_variant
  from public.stock_movements order by created_at limit 1;

  select allow_orders_above_available_stock, allow_negative_stock
    into v_allow_above, v_allow_neg
  from public.company_settings where company_id = v_company;

  insert into public.products (
    company_id, name, sku, selling_price, unit_cost, is_active, created_by, updated_by
  ) values (
    v_company, 'PHASE_E_TEST_DOOR_LOCK', 'PHASE-E-DL-TMP', 100, 50, true, v_emp, v_emp
  ) returning id into v_product;

  select id into v_var_a from public.product_variants
  where product_id = v_product and is_default and deleted_at is null;

  update public.product_variants
  set label = '12"', sku = 'PHASE-E-DL-12', selling_price = 100
  where id = v_var_a;

  insert into public.product_variants (
    company_id, product_id, label, options, sku, selling_price, unit_cost,
    sort_order, is_default, is_active, created_by, updated_by
  ) values (
    v_company, v_product, '16"', '{}'::jsonb, 'PHASE-E-DL-16', 120, 60,
    1, false, true, v_emp, v_emp
  ) returning id into v_var_b;

  -- 1
  begin
    perform public.adjust_inventory(v_branch, v_existing_product, 1, 'adjustment', 'Phase E +1', null, 'test', null);
    perform public.adjust_inventory(v_branch, v_existing_product, -1, 'adjustment', 'Phase E -1', null, 'test', null);
    select quantity into v_existing_qty_after from public.inventory
    where variant_id = v_existing_variant and branch_id = v_branch;
    if v_existing_qty_after = v_existing_qty_before then
      insert into _phase_e_results values ('1_existing_adjust', 'PASS', v_existing_qty_after::text);
    else
      insert into _phase_e_results values ('1_existing_adjust', 'FAIL', format('before=%s after=%s', v_existing_qty_before, v_existing_qty_after));
      update public.inventory set quantity = v_existing_qty_before
      where variant_id = v_existing_variant and branch_id = v_branch;
    end if;
  exception when others then
    insert into _phase_e_results values ('1_existing_adjust', 'FAIL', sqlerrm);
  end;

  -- 3
  begin
    v_inv_a := public.adjust_inventory(v_branch, v_product, 10, 'purchase', 'seed A', null, 'test', null, v_var_a);
    v_inv_b := public.adjust_inventory(v_branch, v_product, 7, 'purchase', 'seed B', null, 'test', null, v_var_b);
    if v_inv_a.quantity = 10 and v_inv_b.quantity = 7 and v_inv_a.id <> v_inv_b.id then
      insert into _phase_e_results values ('3_independent_rows', 'PASS', format('A=%s B=%s', v_inv_a.quantity, v_inv_b.quantity));
    else
      insert into _phase_e_results values ('3_independent_rows', 'FAIL', format('A=%s B=%s', v_inv_a.quantity, v_inv_b.quantity));
    end if;
  exception when others then
    insert into _phase_e_results values ('3_independent_rows', 'FAIL', sqlerrm);
  end;

  -- 4
  begin
    perform public.adjust_inventory(v_branch, v_product, 3, 'purchase', 'bump A', null, 'test', null, v_var_a);
    select quantity into v_existing_qty_after from public.inventory where variant_id = v_var_a and branch_id = v_branch;
    select quantity into v_existing_qty_before from public.inventory where variant_id = v_var_b and branch_id = v_branch;
    if v_existing_qty_after = 13 and v_existing_qty_before = 7 then
      insert into _phase_e_results values ('4_adjust_A_leaves_B', 'PASS', format('A=%s B=%s', v_existing_qty_after, v_existing_qty_before));
    else
      insert into _phase_e_results values ('4_adjust_A_leaves_B', 'FAIL', format('A=%s B=%s', v_existing_qty_after, v_existing_qty_before));
    end if;
  exception when others then
    insert into _phase_e_results values ('4_adjust_A_leaves_B', 'FAIL', sqlerrm);
  end;

  -- 11
  if exists (
    select 1 from public.stock_movements
    where variant_id = v_var_a and product_id = v_product and quantity_delta = 3
  ) then
    insert into _phase_e_results values ('11_movement_variant', 'PASS', 'ok');
  else
    insert into _phase_e_results values ('11_movement_variant', 'FAIL', 'missing');
  end if;

  -- 6
  begin
    update public.company_settings set allow_orders_above_available_stock = false where company_id = v_company;
    v_err := null;
    begin
      perform public.assert_order_line_stock_available(v_company, v_branch, v_var_a, 9999);
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err ilike 'Not enough stock%' then
      insert into _phase_e_results values ('6_allow_above_false', 'PASS', v_err);
    else
      insert into _phase_e_results values ('6_allow_above_false', 'FAIL', coalesce(v_err, 'no error'));
    end if;
  end;

  -- 7
  begin
    update public.company_settings set allow_orders_above_available_stock = true where company_id = v_company;
    perform public.assert_order_line_stock_available(v_company, v_branch, v_var_a, 9999);
    insert into _phase_e_results values ('7_allow_above_true', 'PASS', 'ok');
  exception when others then
    insert into _phase_e_results values ('7_allow_above_true', 'FAIL', sqlerrm);
  end;

  update public.company_settings set allow_orders_above_available_stock = v_allow_above where company_id = v_company;

  -- 8
  begin
    update public.company_settings
    set allow_negative_stock = false, allow_orders_above_available_stock = true
    where company_id = v_company;
    v_err := null;
    begin
      perform public.adjust_inventory(v_branch, v_product, -1000, 'sale', 'neg deny', null, 'test', null, v_var_a);
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err ilike 'Insufficient stock%' then
      insert into _phase_e_results values ('8_allow_neg_false', 'PASS', v_err);
    else
      insert into _phase_e_results values ('8_allow_neg_false', 'FAIL', coalesce(v_err, 'no error'));
    end if;
  end;

  -- 9
  begin
    update public.company_settings set allow_negative_stock = true where company_id = v_company;
    update public.inventory set quantity = 2 where variant_id = v_var_a and branch_id = v_branch;
    v_inv_a := public.adjust_inventory(v_branch, v_product, -5, 'sale', 'neg allow', null, 'test', null, v_var_a);
    if v_inv_a.quantity = -3 then
      insert into _phase_e_results values ('9_allow_neg_true', 'PASS', v_inv_a.quantity::text);
    else
      insert into _phase_e_results values ('9_allow_neg_true', 'FAIL', v_inv_a.quantity::text);
    end if;
    update public.inventory set quantity = 13 where variant_id = v_var_a and branch_id = v_branch;
  exception when others then
    insert into _phase_e_results values ('9_allow_neg_true', 'FAIL', sqlerrm);
  end;

  update public.company_settings
  set allow_negative_stock = v_allow_neg, allow_orders_above_available_stock = v_allow_above
  where company_id = v_company;

  -- 2/5 fulfill
  begin
    update public.inventory set quantity = 20 where variant_id = v_var_a and branch_id = v_branch;
    update public.inventory set quantity = 7 where variant_id = v_var_b and branch_id = v_branch;

    select id into v_customer from public.customers
    where company_id = v_company and deleted_at is null limit 1;

    insert into public.orders (
      company_id, branch_id, customer_id, employee_id, order_number,
      status, subtotal, discount_amount, tax_amount, total, payment_status, created_by, updated_by
    ) values (
      v_company, v_branch, v_customer, v_emp,
      'PHASE-E-' || substr(gen_random_uuid()::text, 1, 8),
      'placed', 100, 0, 0, 100, 'unpaid', v_emp, v_emp
    ) returning id into v_order;

    insert into public.order_items (
      company_id, order_id, product_id, variant_id, product_name, variant_label, sku,
      quantity, unit_price, line_total, created_by, updated_by
    ) values (
      v_company, v_order, v_product, v_var_a, 'PHASE_E_TEST_DOOR_LOCK', '12"', 'PHASE-E-DL-12',
      4, 100, 400, v_emp, v_emp
    ) returning id into v_item;

    perform public.fulfill_order_items(
      v_order,
      jsonb_build_array(jsonb_build_object('order_item_id', v_item, 'quantity', 4))
    );

    select quantity into v_existing_qty_after from public.inventory where variant_id = v_var_a and branch_id = v_branch;
    select quantity into v_existing_qty_before from public.inventory where variant_id = v_var_b and branch_id = v_branch;

    if v_existing_qty_after = 16 and v_existing_qty_before = 7 then
      insert into _phase_e_results values ('2_5_fulfill_A_only', 'PASS', format('A=%s B=%s', v_existing_qty_after, v_existing_qty_before));
    else
      insert into _phase_e_results values ('2_5_fulfill_A_only', 'FAIL', format('A=%s B=%s', v_existing_qty_after, v_existing_qty_before));
    end if;
  exception when others then
    insert into _phase_e_results values ('2_5_fulfill_A_only', 'FAIL', sqlerrm);
  end;

  -- 10
  begin
    update public.inventory set quantity = 100 where variant_id = v_var_a and branch_id = v_branch;
    perform public.adjust_inventory(v_branch, v_product, -3, 'sale', 'c1', null, 'test', null, v_var_a);
    perform public.adjust_inventory(v_branch, v_product, -4, 'sale', 'c2', null, 'test', null, v_var_a);
    select quantity into v_existing_qty_after from public.inventory where variant_id = v_var_a and branch_id = v_branch;
    if v_existing_qty_after = 93 then
      insert into _phase_e_results values ('10_concurrency_seq', 'PASS', v_existing_qty_after::text);
    else
      insert into _phase_e_results values ('10_concurrency_seq', 'FAIL', v_existing_qty_after::text);
    end if;
  exception when others then
    insert into _phase_e_results values ('10_concurrency_seq', 'FAIL', sqlerrm);
  end;

  -- 12
  if v_hist_mov_variant is not null and exists (
    select 1 from public.stock_movements where variant_id = v_hist_mov_variant
  ) then
    insert into _phase_e_results values ('12_hist_movements', 'PASS', v_hist_mov_variant::text);
  else
    insert into _phase_e_results values ('12_hist_movements', 'FAIL', 'missing');
  end if;

  -- 13
  if (select coalesce(sum(quantity),0) from public.order_items where order_id is distinct from coalesce(v_order, '00000000-0000-0000-0000-000000000000'::uuid)
        and product_id is distinct from v_product) = 27
     and (select coalesce(sum(line_total),0) from public.order_items where order_id is distinct from coalesce(v_order, '00000000-0000-0000-0000-000000000000'::uuid)
        and product_id is distinct from v_product) = 2954 then
    insert into _phase_e_results values ('13_hist_order_items', 'PASS', 'ok');
  else
    insert into _phase_e_results values ('13_hist_order_items', 'FAIL', 'totals changed');
  end if;

  -- SEC
  begin
    v_err := null;
    begin
      perform public.adjust_inventory(v_branch, v_existing_product, 1, 'adjustment', 'bad', null, 'test', null, v_var_a);
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err ilike '%does not belong%' then
      insert into _phase_e_results values ('SEC_mismatch', 'PASS', v_err);
    else
      insert into _phase_e_results values ('SEC_mismatch', 'FAIL', coalesce(v_err, 'no error'));
    end if;
  end;

  -- cleanup inside txn then rollback? We'll commit cleanup by deleting then commit.
  if v_order is not null then
    delete from public.order_items where order_id = v_order;
    -- AR side effects from fulfill may exist; soft-cancel order
    update public.orders set status = 'cancelled', deleted_at = timezone('utc', now()) where id = v_order;
  end if;

  delete from public.stock_movements where product_id = v_product;
  delete from public.stock_movements
  where reference_type = 'test'
    and created_by = v_emp
    and reason in ('Phase E +1','Phase E -1','Phase E test +1','Phase E test -1');

  delete from public.inventory where product_id = v_product;
  delete from public.product_variants where product_id = v_product;
  delete from public.products where id = v_product;

  update public.company_settings
  set allow_negative_stock = v_allow_neg, allow_orders_above_available_stock = v_allow_above
  where company_id = v_company;

  -- restore existing product qty if needed
  update public.inventory set quantity = (
    select q from (select v_existing_qty_before as q) s
  )
  where variant_id = v_existing_variant and branch_id = v_branch
    and quantity is distinct from v_existing_qty_before;
end;
$tests$;

select * from _phase_e_results order by test_id;

-- Keep production clean: roll back ALL test mutations including cleanup deletes of test-only rows.
-- Actually we need cleanup committed if we created rows... Use commit of cleanup only.
-- Safer: rollback entire test and accept no persistent test residue.
rollback;
