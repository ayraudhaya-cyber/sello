-- =============================================================================
-- seed_dev.sql
-- DEVELOPMENT / LOCAL ONLY — do not run against production.
--
-- Seeds a complete Unitech demo tenant for Sello auth + experience routing.
-- Assumes Migration 001 has been applied (roles already seeded).
--
-- Does NOT:
--   - recreate roles
--   - create auth.users (create those in Supabase Auth Dashboard / Admin API)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Supabase Auth user UUIDs
-- -----------------------------------------------------------------------------
-- Create three users in Supabase Authentication (email/password), then paste
-- their `auth.users.id` values below. Leave as NULL to seed employees first
-- and link auth later via the UPDATE helpers at the bottom of this file.
--
-- Example emails (suggested when creating Auth users):
--   owner@unitech.demo
--   manager@unitech.demo
--   sales@unitech.demo
-- -----------------------------------------------------------------------------

do $$
declare
  -- >>> UPDATE THESE with real auth.users.id values from Supabase Auth <<<
  v_owner_auth_user_id   uuid := null; -- Owner            auth.users.id
  v_manager_auth_user_id uuid := null; -- Manager          auth.users.id
  v_sales_auth_user_id   uuid := null; -- Sales Rep        auth.users.id
  -- >>> ----------------------------------------------------------------- <<<

  v_company_id uuid;
  v_branch_id  uuid;
  v_owner_role_id uuid;
  v_manager_role_id uuid;
  v_sales_role_id uuid;
  v_owner_employee_id uuid;
  v_beverages_id uuid;
  v_dairy_id uuid;
  v_grocery_id uuid;
  v_product_id uuid;
begin
  -- ---------------------------------------------------------------------------
  -- 2) Resolve existing system roles (do not insert roles)
  -- ---------------------------------------------------------------------------
  select id into strict v_owner_role_id
  from public.roles
  where code = 'owner';

  select id into strict v_manager_role_id
  from public.roles
  where code = 'manager';

  select id into strict v_sales_role_id
  from public.roles
  where code = 'sales_representative';

  -- ---------------------------------------------------------------------------
  -- 3) Company — Unitech
  -- ---------------------------------------------------------------------------
  insert into public.companies (
    name,
    legal_name,
    company_code,
    slug,
    is_active
  )
  values (
    'Unitech',
    'Unitech',
    'UNITECH',
    'unitech',
    true
  )
  on conflict (company_code) where deleted_at is null
  do update set
    name = excluded.name,
    legal_name = excluded.legal_name,
    slug = excluded.slug,
    is_active = true,
    updated_at = timezone('utc', now()),
    deleted_at = null
  returning id into v_company_id;

  -- If conflict path did not return (edge cases), resolve by code.
  if v_company_id is null then
    select id into strict v_company_id
    from public.companies
    where company_code = 'UNITECH'
      and deleted_at is null;
  end if;

  -- ---------------------------------------------------------------------------
  -- 4) Company settings (minimal defaults for the demo tenant)
  -- ---------------------------------------------------------------------------
  insert into public.company_settings (
    company_id,
    primary_color,
    secondary_color,
    currency,
    timezone,
    locale,
    country,
    custom_branding_enabled,
    owner_setup_completed
  )
  values (
    v_company_id,
    '#9619F1',
    '#4237E7',
    'USD',
    'UTC',
    'en-US',
    'US',
    true,
    true
  )
  on conflict (company_id)
  do update set
    primary_color = excluded.primary_color,
    secondary_color = excluded.secondary_color,
    custom_branding_enabled = true,
    owner_setup_completed = true,
    updated_at = timezone('utc', now());

  -- ---------------------------------------------------------------------------
  -- 5) Branch — Head Office
  -- ---------------------------------------------------------------------------
  insert into public.branches (
    company_id,
    name,
    code,
    is_active
  )
  values (
    v_company_id,
    'Head Office',
    'HO',
    true
  )
  on conflict (company_id, code) where deleted_at is null
  do update set
    name = excluded.name,
    is_active = true,
    updated_at = timezone('utc', now()),
    deleted_at = null
  returning id into v_branch_id;

  if v_branch_id is null then
    select id into strict v_branch_id
    from public.branches
    where company_id = v_company_id
      and code = 'HO'
      and deleted_at is null;
  end if;

  -- ---------------------------------------------------------------------------
  -- 6) Employees (Owner, Manager, Sales Representative)
  -- ---------------------------------------------------------------------------
  -- user_id is set from the variables at the top of this script.
  -- If those variables are null, employees are created without auth linkage;
  -- use the UPDATE helpers at the bottom after Auth users exist.

  insert into public.employees (
    company_id,
    branch_id,
    role_id,
    user_id,
    email,
    full_name,
    is_active
  )
  values (
    v_company_id,
    v_branch_id,
    v_owner_role_id,
    v_owner_auth_user_id, -- <<< Owner auth.users.id
    'owner@unitech.demo',
    'Unitech Owner',
    true
  )
  on conflict (company_id, email) where deleted_at is null
  do update set
    branch_id = excluded.branch_id,
    role_id = excluded.role_id,
    user_id = coalesce(excluded.user_id, public.employees.user_id),
    full_name = excluded.full_name,
    is_active = true,
    updated_at = timezone('utc', now()),
    deleted_at = null;

  insert into public.employees (
    company_id,
    branch_id,
    role_id,
    user_id,
    email,
    full_name,
    is_active
  )
  values (
    v_company_id,
    v_branch_id,
    v_manager_role_id,
    v_manager_auth_user_id, -- <<< Manager auth.users.id
    'manager@unitech.demo',
    'Unitech Manager',
    true
  )
  on conflict (company_id, email) where deleted_at is null
  do update set
    branch_id = excluded.branch_id,
    role_id = excluded.role_id,
    user_id = coalesce(excluded.user_id, public.employees.user_id),
    full_name = excluded.full_name,
    is_active = true,
    updated_at = timezone('utc', now()),
    deleted_at = null;

  insert into public.employees (
    company_id,
    branch_id,
    role_id,
    user_id,
    email,
    full_name,
    is_active
  )
  values (
    v_company_id,
    v_branch_id,
    v_sales_role_id,
    v_sales_auth_user_id, -- <<< Sales Representative auth.users.id
    'sales@unitech.demo',
    'Unitech Sales Rep',
    true
  )
  on conflict (company_id, email) where deleted_at is null
  do update set
    branch_id = excluded.branch_id,
    role_id = excluded.role_id,
    user_id = coalesce(excluded.user_id, public.employees.user_id),
    full_name = excluded.full_name,
    is_active = true,
    updated_at = timezone('utc', now()),
    deleted_at = null;

  select id into strict v_owner_employee_id
  from public.employees
  where company_id = v_company_id
    and email = 'owner@unitech.demo'
    and deleted_at is null;

  -- ---------------------------------------------------------------------------
  -- 7) Product catalog demo data
  -- ---------------------------------------------------------------------------
  insert into public.categories (
    company_id,
    name,
    sort_order,
    created_by,
    updated_by
  )
  values (
    v_company_id,
    'Beverages',
    10,
    v_owner_employee_id,
    v_owner_employee_id
  )
  on conflict (company_id, name) where deleted_at is null
  do update set
    sort_order = excluded.sort_order,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_beverages_id;

  if v_beverages_id is null then
    select id into strict v_beverages_id
    from public.categories
    where company_id = v_company_id
      and name = 'Beverages'
      and deleted_at is null;
  end if;

  insert into public.categories (
    company_id,
    name,
    sort_order,
    created_by,
    updated_by
  )
  values (
    v_company_id,
    'Dairy',
    20,
    v_owner_employee_id,
    v_owner_employee_id
  )
  on conflict (company_id, name) where deleted_at is null
  do update set
    sort_order = excluded.sort_order,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_dairy_id;

  if v_dairy_id is null then
    select id into strict v_dairy_id
    from public.categories
    where company_id = v_company_id
      and name = 'Dairy'
      and deleted_at is null;
  end if;

  insert into public.categories (
    company_id,
    name,
    sort_order,
    created_by,
    updated_by
  )
  values (
    v_company_id,
    'Grocery',
    30,
    v_owner_employee_id,
    v_owner_employee_id
  )
  on conflict (company_id, name) where deleted_at is null
  do update set
    sort_order = excluded.sort_order,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_grocery_id;

  if v_grocery_id is null then
    select id into strict v_grocery_id
    from public.categories
    where company_id = v_company_id
      and name = 'Grocery'
      and deleted_at is null;
  end if;

  insert into public.products (
    company_id,
    category_id,
    sku,
    barcode,
    name,
    brand,
    description,
    unit_label,
    unit_cost,
    selling_price,
    is_active,
    created_by,
    updated_by
  )
  values (
    v_company_id,
    v_beverages_id,
    'COCO-1L',
    '4792038001011',
    'Coca-Cola 1L',
    'Coca-Cola',
    'Classic sparkling soft drink in a 1 liter bottle.',
    'Bottle',
    1.10,
    1.65,
    true,
    v_owner_employee_id,
    v_owner_employee_id
  )
  on conflict (company_id, sku) where deleted_at is null
  do update set
    category_id = excluded.category_id,
    barcode = excluded.barcode,
    name = excluded.name,
    brand = excluded.brand,
    description = excluded.description,
    unit_label = excluded.unit_label,
    unit_cost = excluded.unit_cost,
    selling_price = excluded.selling_price,
    is_active = true,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_product_id;

  insert into public.inventory (
    company_id,
    branch_id,
    product_id,
    quantity,
    reorder_level,
    created_by,
    updated_by
  )
  values (
    v_company_id,
    v_branch_id,
    v_product_id,
    144,
    48,
    v_owner_employee_id,
    v_owner_employee_id
  )
  on conflict (company_id, branch_id, product_id)
  do update set
    quantity = excluded.quantity,
    reorder_level = excluded.reorder_level,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now());

  insert into public.products (
    company_id, category_id, sku, barcode, name, brand, description,
    unit_label, unit_cost, selling_price, is_active, created_by, updated_by
  )
  values (
    v_company_id, v_beverages_id, 'PEPSI-500', '4792038002056',
    'Pepsi 500ml', 'Pepsi', 'Carbonated soft drink in a grab-and-go bottle.',
    'Bottle', 0.62, 0.95, true, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, sku) where deleted_at is null
  do update set
    category_id = excluded.category_id,
    barcode = excluded.barcode,
    name = excluded.name,
    brand = excluded.brand,
    description = excluded.description,
    unit_label = excluded.unit_label,
    unit_cost = excluded.unit_cost,
    selling_price = excluded.selling_price,
    is_active = true,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_product_id;

  insert into public.inventory (
    company_id, branch_id, product_id, quantity, reorder_level, created_by, updated_by
  )
  values (
    v_company_id, v_branch_id, v_product_id, 220, 72, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, branch_id, product_id)
  do update set
    quantity = excluded.quantity,
    reorder_level = excluded.reorder_level,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now());

  insert into public.products (
    company_id, category_id, sku, barcode, name, brand, description,
    unit_label, unit_cost, selling_price, is_active, created_by, updated_by
  )
  values (
    v_company_id, v_grocery_id, 'NEST-MILK-400', '7613036934689',
    'Nestle Milk Powder', 'Nestle', 'Instant full-cream milk powder tin.',
    'Tin', 3.45, 4.80, true, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, sku) where deleted_at is null
  do update set
    category_id = excluded.category_id,
    barcode = excluded.barcode,
    name = excluded.name,
    brand = excluded.brand,
    description = excluded.description,
    unit_label = excluded.unit_label,
    unit_cost = excluded.unit_cost,
    selling_price = excluded.selling_price,
    is_active = true,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_product_id;

  insert into public.inventory (
    company_id, branch_id, product_id, quantity, reorder_level, created_by, updated_by
  )
  values (
    v_company_id, v_branch_id, v_product_id, 86, 24, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, branch_id, product_id)
  do update set
    quantity = excluded.quantity,
    reorder_level = excluded.reorder_level,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now());

  insert into public.products (
    company_id, category_id, sku, barcode, name, brand, description,
    unit_label, unit_cost, selling_price, is_active, created_by, updated_by
  )
  values (
    v_company_id, v_dairy_id, 'ANCH-BUTTER-200', '9400547003211',
    'Anchor Butter', 'Anchor', 'Salted butter block for retail and food service.',
    'Pack', 2.10, 2.95, true, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, sku) where deleted_at is null
  do update set
    category_id = excluded.category_id,
    barcode = excluded.barcode,
    name = excluded.name,
    brand = excluded.brand,
    description = excluded.description,
    unit_label = excluded.unit_label,
    unit_cost = excluded.unit_cost,
    selling_price = excluded.selling_price,
    is_active = true,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_product_id;

  insert into public.inventory (
    company_id, branch_id, product_id, quantity, reorder_level, created_by, updated_by
  )
  values (
    v_company_id, v_branch_id, v_product_id, 64, 20, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, branch_id, product_id)
  do update set
    quantity = excluded.quantity,
    reorder_level = excluded.reorder_level,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now());

  insert into public.products (
    company_id, category_id, sku, barcode, name, brand, description,
    unit_label, unit_cost, selling_price, is_active, created_by, updated_by
  )
  values (
    v_company_id, v_beverages_id, 'SPRITE-500', '5449000014219',
    'Sprite 500ml', 'Sprite', 'Lemon-lime sparkling drink for impulse sales.',
    'Bottle', 0.60, 0.92, true, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, sku) where deleted_at is null
  do update set
    category_id = excluded.category_id,
    barcode = excluded.barcode,
    name = excluded.name,
    brand = excluded.brand,
    description = excluded.description,
    unit_label = excluded.unit_label,
    unit_cost = excluded.unit_cost,
    selling_price = excluded.selling_price,
    is_active = true,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_product_id;

  insert into public.inventory (
    company_id, branch_id, product_id, quantity, reorder_level, created_by, updated_by
  )
  values (
    v_company_id, v_branch_id, v_product_id, 175, 60, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, branch_id, product_id)
  do update set
    quantity = excluded.quantity,
    reorder_level = excluded.reorder_level,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now());

  insert into public.products (
    company_id, category_id, sku, barcode, name, brand, description,
    unit_label, unit_cost, selling_price, is_active, created_by, updated_by
  )
  values (
    v_company_id, v_beverages_id, 'OJ-1L', '8901234567890',
    'Orange Juice', 'Sunfresh', 'Ready-to-serve orange juice carton.',
    'Carton', 1.48, 2.15, true, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, sku) where deleted_at is null
  do update set
    category_id = excluded.category_id,
    barcode = excluded.barcode,
    name = excluded.name,
    brand = excluded.brand,
    description = excluded.description,
    unit_label = excluded.unit_label,
    unit_cost = excluded.unit_cost,
    selling_price = excluded.selling_price,
    is_active = true,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now())
  returning id into v_product_id;

  insert into public.inventory (
    company_id, branch_id, product_id, quantity, reorder_level, created_by, updated_by
  )
  values (
    v_company_id, v_branch_id, v_product_id, 52, 18, v_owner_employee_id, v_owner_employee_id
  )
  on conflict (company_id, branch_id, product_id)
  do update set
    quantity = excluded.quantity,
    reorder_level = excluded.reorder_level,
    updated_by = excluded.updated_by,
    updated_at = timezone('utc', now());

  raise notice 'seed_dev: Unitech demo tenant ready (company_id=%)', v_company_id;
  raise notice 'seed_dev: branch Head Office (branch_id=%)', v_branch_id;
  raise notice 'seed_dev: employees owner@ / manager@ / sales@ unitech.demo';
  if v_owner_auth_user_id is null
     or v_manager_auth_user_id is null
     or v_sales_auth_user_id is null then
    raise notice 'seed_dev: one or more auth user UUIDs are NULL — link them (see script footer).';
  end if;
end $$;

-- =============================================================================
-- Optional: link Auth users AFTER re-running the block above
-- =============================================================================
-- Prefer setting the three variables at the top of this script and re-running.
-- Or run these UPDATEs once Auth users exist:
--
--   update public.employees
--   set user_id = '<OWNER_AUTH_USER_UUID>',
--       updated_at = timezone('utc', now())
--   where email = 'owner@unitech.demo'
--     and deleted_at is null;
--
--   update public.employees
--   set user_id = '<MANAGER_AUTH_USER_UUID>',
--       updated_at = timezone('utc', now())
--   where email = 'manager@unitech.demo'
--     and deleted_at is null;
--
--   update public.employees
--   set user_id = '<SALES_AUTH_USER_UUID>',
--       updated_at = timezone('utc', now())
--   where email = 'sales@unitech.demo'
--     and deleted_at is null;
-- =============================================================================
