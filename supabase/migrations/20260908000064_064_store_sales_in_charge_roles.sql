-- =============================================================================
-- 064 — Store In-charge + Sales In-charge roles
--
-- Adds two Hub operational roles to the global roles catalog and seeds
-- role_module_access so has_module_permission() can deny restricted modules
-- (missing rows currently fall through to true — so we seed a full matrix).
--
-- Store In-charge may create/edit products and VIEW cost via
-- can_view_product_cost(). Cost EDIT is not a separate module verb yet.
--
-- Does NOT alter Owner / Manager / Sales Representative module matrices.
-- Does NOT invent branch RLS (current_branch_id exists; policies remain
-- company-scoped — report as a known gap).
-- =============================================================================

insert into public.roles (code, name, description, display_order)
values
  (
    'store_in_charge',
    'Store In-charge',
    'Manages stock, inventory and store deliveries.',
    10
  ),
  (
    'sales_in_charge',
    'Sales In-charge',
    'Manages sales, customers and the sales team.',
    11
  )
on conflict (code) do update
set
  name = excluded.name,
  description = excluded.description,
  display_order = excluded.display_order,
  updated_at = timezone('utc', now());

create or replace function public._seed_role_module_access(
  p_role_code text,
  p_module_key text,
  p_can_view boolean,
  p_can_create boolean,
  p_can_edit boolean,
  p_can_delete boolean,
  p_can_approve boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
  v_manage boolean := (p_can_create or p_can_edit or p_can_delete or p_can_approve);
begin
  select id into v_role_id from public.roles where code = p_role_code;
  if v_role_id is null then
    raise exception 'Unknown role code: %', p_role_code;
  end if;

  update public.role_module_access
  set
    can_view = p_can_view,
    can_manage = v_manage,
    can_create = p_can_create,
    can_edit = p_can_edit,
    can_delete = p_can_delete,
    can_approve = p_can_approve,
    updated_at = timezone('utc', now())
  where role_id = v_role_id
    and module_key = p_module_key
    and company_id is null;

  if found then
    return;
  end if;

  insert into public.role_module_access (
    company_id,
    role_id,
    module_key,
    can_view,
    can_manage,
    can_create,
    can_edit,
    can_delete,
    can_approve
  ) values (
    null,
    v_role_id,
    p_module_key,
    p_can_view,
    v_manage,
    p_can_create,
    p_can_edit,
    p_can_delete,
    p_can_approve
  );
end;
$$;

-- Store In-charge
-- Products: create + edit (store team may add catalog items). No delete.
select public._seed_role_module_access(
  'store_in_charge', 'products', true, true, true, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'inventory', true, true, true, true, false
);
select public._seed_role_module_access(
  'store_in_charge', 'orders', true, false, true, false, true
);
select public._seed_role_module_access(
  'store_in_charge', 'customers', true, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'notifications', true, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'suppliers', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'payments', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'reports', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'settings', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'employees', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'sales', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'schedule', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'visits', false, false, false, false, false
);
select public._seed_role_module_access(
  'store_in_charge', 'intelligence', false, false, false, false, false
);

-- Sales In-charge
select public._seed_role_module_access(
  'sales_in_charge', 'orders', true, true, true, true, true
);
select public._seed_role_module_access(
  'sales_in_charge', 'customers', true, true, true, true, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'employees', true, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'reports', true, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'products', true, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'inventory', true, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'payments', true, true, true, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'schedule', true, true, true, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'visits', true, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'notifications', true, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'intelligence', true, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'suppliers', false, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'settings', false, false, false, false, false
);
select public._seed_role_module_access(
  'sales_in_charge', 'sales', false, false, false, false, false
);

drop function if exists public._seed_role_module_access(
  text, text, boolean, boolean, boolean, boolean, boolean
);

-- ---------------------------------------------------------------------------
-- Product cost VIEW — Store In-charge may see unit cost (same gate as Hub).
-- Cost WRITE is not a separate module permission today: product create/edit
-- upserts unit_cost. Restricting cost edits needs a dedicated trigger/RPC
-- (not invented here). Owner/Manager remain the only roles that historically
-- could view cost; Sales Rep stays masked.
-- ---------------------------------------------------------------------------

create or replace function public.can_view_product_cost()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_role_code() in (
    'owner',
    'manager',
    'store_in_charge'
  );
$$;

comment on function public.can_view_product_cost() is
  'True when cost_price(products) may return unit_cost. '
  'Owner, Manager, Store In-charge. Sales Rep and Sales In-charge stay masked.';
