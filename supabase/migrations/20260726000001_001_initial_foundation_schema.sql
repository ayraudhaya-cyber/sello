-- =============================================================================
-- Migration 001 — Initial Foundation Schema
-- Project: Sello
-- Engine:  PostgreSQL (Supabase-compatible)
--
-- Purpose:
--   Production-ready multi-tenant foundation for the initial Sello release.
--   Covers tenancy, people, catalog, stock, and sales orders only.
--
-- Entities:
--   companies, company_settings, branches, roles, employees,
--   customers, categories, products, product_images, inventory,
--   orders, order_items
--
-- Notes:
--   - UUID primary keys via gen_random_uuid() (pgcrypto)
--   - Soft deletes use deleted_at + partial unique indexes
--   - created_by / updated_by reference employees (nullable)
--   - RLS policies are intentionally deferred to a later migration
-- =============================================================================

create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- Shared: updated_at trigger
-- -----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- roles (global system catalog)
-- -----------------------------------------------------------------------------

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  description text,
  display_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint roles_code_key unique (code),
  constraint roles_code_format check (code ~ '^[a-z][a-z0-9_]*$'),
  constraint roles_name_not_blank check (length(trim(name)) > 0)
);

create index roles_display_order_idx on public.roles (display_order, name);

create trigger trg_roles_set_updated_at
before update on public.roles
for each row execute function public.set_updated_at();

insert into public.roles (code, name, description, display_order) values
  ('owner', 'Owner', 'Full business administration access to Sello Hub', 1),
  ('manager', 'Manager', 'Operational management access to Sello Hub', 2),
  ('sales_representative', 'Sales Representative', 'Field sales access to Sello', 3);

-- -----------------------------------------------------------------------------
-- companies
-- -----------------------------------------------------------------------------

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  company_code text not null,
  slug text not null,
  is_active boolean not null default true,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint companies_name_not_blank check (length(trim(name)) > 0),
  constraint companies_company_code_not_blank check (length(trim(company_code)) > 0),
  constraint companies_slug_not_blank check (length(trim(slug)) > 0),
  constraint companies_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

create unique index companies_company_code_active_key
  on public.companies (company_code)
  where deleted_at is null;

create unique index companies_slug_active_key
  on public.companies (slug)
  where deleted_at is null;

create index companies_is_active_idx on public.companies (is_active)
  where deleted_at is null;
create index companies_deleted_at_idx on public.companies (deleted_at);

create trigger trg_companies_set_updated_at
before update on public.companies
for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- company_settings (1:1 branding & localization)
-- -----------------------------------------------------------------------------

create table public.company_settings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  logo_url text,
  primary_color text,
  secondary_color text,
  currency text not null default 'USD',
  timezone text not null default 'UTC',
  locale text not null default 'en-US',
  country text,
  date_format text not null default 'yyyy-MM-dd',
  time_format text not null default 'HH:mm',
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint company_settings_company_id_key unique (company_id),
  constraint company_settings_currency_format check (currency ~ '^[A-Z]{3}$'),
  constraint company_settings_locale_format
    check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  constraint company_settings_primary_color_format
    check (primary_color is null or primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint company_settings_secondary_color_format
    check (secondary_color is null or secondary_color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint company_settings_timezone_not_blank check (length(trim(timezone)) > 0),
  constraint company_settings_locale_not_blank check (length(trim(locale)) > 0),
  constraint company_settings_date_format_not_blank check (length(trim(date_format)) > 0),
  constraint company_settings_time_format_not_blank check (length(trim(time_format)) > 0)
);

create trigger trg_company_settings_set_updated_at
before update on public.company_settings
for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- branches
-- -----------------------------------------------------------------------------

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  name text not null,
  code text not null,
  phone text,
  email text,
  manager_name text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  postal_code text,
  country text,
  is_active boolean not null default true,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint branches_name_not_blank check (length(trim(name)) > 0),
  constraint branches_code_not_blank check (length(trim(code)) > 0),
  constraint branches_email_format
    check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

create unique index branches_company_code_active_key
  on public.branches (company_id, code)
  where deleted_at is null;

create index branches_company_id_idx on public.branches (company_id)
  where deleted_at is null;
create index branches_company_active_idx on public.branches (company_id, is_active)
  where deleted_at is null;

create trigger trg_branches_set_updated_at
before update on public.branches
for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- employees
-- -----------------------------------------------------------------------------

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid references public.branches (id) on delete set null,
  role_id uuid not null references public.roles (id) on delete restrict,
  user_id uuid unique references auth.users (id) on delete set null,
  email text not null,
  full_name text not null,
  phone text,
  avatar_url text,
  is_active boolean not null default true,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint employees_full_name_not_blank check (length(trim(full_name)) > 0),
  constraint employees_email_not_blank check (length(trim(email)) > 0),
  constraint employees_email_format check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

create unique index employees_company_email_active_key
  on public.employees (company_id, email)
  where deleted_at is null;

create index employees_company_id_idx on public.employees (company_id)
  where deleted_at is null;
create index employees_branch_id_idx on public.employees (branch_id)
  where deleted_at is null;
create index employees_role_id_idx on public.employees (role_id);
create index employees_user_id_idx on public.employees (user_id)
  where user_id is not null and deleted_at is null;
create index employees_company_active_idx on public.employees (company_id, is_active)
  where deleted_at is null;

create trigger trg_employees_set_updated_at
before update on public.employees
for each row execute function public.set_updated_at();

-- Audit FKs that depend on employees (deferred until employees exists)
alter table public.companies
  add constraint companies_created_by_fkey
    foreign key (created_by) references public.employees (id) on delete set null,
  add constraint companies_updated_by_fkey
    foreign key (updated_by) references public.employees (id) on delete set null;

alter table public.company_settings
  add constraint company_settings_created_by_fkey
    foreign key (created_by) references public.employees (id) on delete set null,
  add constraint company_settings_updated_by_fkey
    foreign key (updated_by) references public.employees (id) on delete set null;

alter table public.branches
  add constraint branches_created_by_fkey
    foreign key (created_by) references public.employees (id) on delete set null,
  add constraint branches_updated_by_fkey
    foreign key (updated_by) references public.employees (id) on delete set null;

alter table public.employees
  add constraint employees_created_by_fkey
    foreign key (created_by) references public.employees (id) on delete set null,
  add constraint employees_updated_by_fkey
    foreign key (updated_by) references public.employees (id) on delete set null;

-- Ensure employee branch belongs to the same company
create or replace function public.validate_employee_branch_company()
returns trigger
language plpgsql
as $$
begin
  if new.branch_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'employees.branch_id must belong to the same company';
  end if;

  return new;
end;
$$;

create trigger trg_employees_validate_branch_company
before insert or update of branch_id, company_id on public.employees
for each row execute function public.validate_employee_branch_company();

-- -----------------------------------------------------------------------------
-- customers
-- -----------------------------------------------------------------------------

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid references public.branches (id) on delete set null,
  code text,
  name text not null,
  contact_name text,
  phone text,
  email text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  postal_code text,
  country text,
  notes text,
  credit_limit numeric(14, 2) not null default 0,
  current_balance numeric(14, 2) not null default 0,
  is_active boolean not null default true,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint customers_name_not_blank check (length(trim(name)) > 0),
  constraint customers_credit_limit_non_negative check (credit_limit >= 0),
  constraint customers_email_format
    check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

create unique index customers_company_code_active_key
  on public.customers (company_id, code)
  where code is not null and deleted_at is null;

create index customers_company_id_idx on public.customers (company_id)
  where deleted_at is null;
create index customers_branch_id_idx on public.customers (branch_id)
  where deleted_at is null;
create index customers_company_name_idx on public.customers (company_id, name)
  where deleted_at is null;
create index customers_company_active_idx on public.customers (company_id, is_active)
  where deleted_at is null;

create trigger trg_customers_set_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create or replace function public.validate_customer_branch_company()
returns trigger
language plpgsql
as $$
begin
  if new.branch_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'customers.branch_id must belong to the same company';
  end if;

  return new;
end;
$$;

create trigger trg_customers_validate_branch_company
before insert or update of branch_id, company_id on public.customers
for each row execute function public.validate_customer_branch_company();

-- -----------------------------------------------------------------------------
-- categories
-- -----------------------------------------------------------------------------

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  name text not null,
  sort_order integer not null default 0,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint categories_name_not_blank check (length(trim(name)) > 0)
);

create unique index categories_company_name_active_key
  on public.categories (company_id, name)
  where deleted_at is null;

create index categories_company_id_idx on public.categories (company_id)
  where deleted_at is null;
create index categories_company_sort_idx on public.categories (company_id, sort_order)
  where deleted_at is null;

create trigger trg_categories_set_updated_at
before update on public.categories
for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------

create table public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  category_id uuid references public.categories (id) on delete set null,
  sku text not null,
  barcode text,
  name text not null,
  description text,
  unit_label text,
  cost_price numeric(14, 2) not null default 0,
  selling_price numeric(14, 2) not null default 0,
  is_active boolean not null default true,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint products_name_not_blank check (length(trim(name)) > 0),
  constraint products_sku_not_blank check (length(trim(sku)) > 0),
  constraint products_cost_price_non_negative check (cost_price >= 0),
  constraint products_selling_price_non_negative check (selling_price >= 0),
  constraint products_barcode_not_blank
    check (barcode is null or length(trim(barcode)) > 0)
);

create unique index products_company_sku_active_key
  on public.products (company_id, sku)
  where deleted_at is null;

create unique index products_company_barcode_active_key
  on public.products (company_id, barcode)
  where barcode is not null and deleted_at is null;

create index products_company_id_idx on public.products (company_id)
  where deleted_at is null;
create index products_category_id_idx on public.products (category_id)
  where deleted_at is null;
create index products_company_name_idx on public.products (company_id, name)
  where deleted_at is null;
create index products_company_active_idx on public.products (company_id, is_active)
  where deleted_at is null;
create index products_company_barcode_idx on public.products (company_id, barcode)
  where barcode is not null and deleted_at is null;

create trigger trg_products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create or replace function public.validate_product_category_company()
returns trigger
language plpgsql
as $$
begin
  if new.category_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.categories c
    where c.id = new.category_id
      and c.company_id = new.company_id
      and c.deleted_at is null
  ) then
    raise exception 'products.category_id must belong to the same company';
  end if;

  return new;
end;
$$;

create trigger trg_products_validate_category_company
before insert or update of category_id, company_id on public.products
for each row execute function public.validate_product_category_company();

-- -----------------------------------------------------------------------------
-- product_images
-- -----------------------------------------------------------------------------

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete cascade,
  storage_path text not null,
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint product_images_storage_path_not_blank check (length(trim(storage_path)) > 0)
);

create index product_images_product_id_idx on public.product_images (product_id);
create index product_images_company_id_idx on public.product_images (company_id);
create index product_images_product_sort_idx on public.product_images (product_id, sort_order);

-- At most one primary image per product
create unique index product_images_one_primary_per_product_idx
  on public.product_images (product_id)
  where is_primary;

create trigger trg_product_images_set_updated_at
before update on public.product_images
for each row execute function public.set_updated_at();

create or replace function public.validate_product_image_company()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
      and p.deleted_at is null
  ) then
    raise exception 'product_images.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

create trigger trg_product_images_validate_company
before insert or update of product_id, company_id on public.product_images
for each row execute function public.validate_product_image_company();

-- -----------------------------------------------------------------------------
-- inventory (product stock per branch)
-- -----------------------------------------------------------------------------

create table public.inventory (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  quantity numeric(14, 3) not null default 0,
  reorder_level numeric(14, 3),
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint inventory_quantity_non_negative check (quantity >= 0),
  constraint inventory_reorder_level_non_negative
    check (reorder_level is null or reorder_level >= 0),
  constraint inventory_company_branch_product_key unique (company_id, branch_id, product_id)
);

create index inventory_company_id_idx on public.inventory (company_id);
create index inventory_branch_id_idx on public.inventory (branch_id);
create index inventory_product_id_idx on public.inventory (product_id);
create index inventory_branch_product_idx on public.inventory (branch_id, product_id);

create trigger trg_inventory_set_updated_at
before update on public.inventory
for each row execute function public.set_updated_at();

create or replace function public.validate_inventory_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'inventory.branch_id must belong to the same company';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
      and p.deleted_at is null
  ) then
    raise exception 'inventory.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

create trigger trg_inventory_validate_tenant_scope
before insert or update of company_id, branch_id, product_id on public.inventory
for each row execute function public.validate_inventory_tenant_scope();

-- -----------------------------------------------------------------------------
-- orders
-- -----------------------------------------------------------------------------

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete restrict,
  employee_id uuid not null references public.employees (id) on delete restrict,
  order_number text not null,
  status text not null default 'draft',
  ordered_at timestamptz not null default timezone('utc', now()),
  notes text,
  signature_storage_path text,
  subtotal numeric(14, 2) not null default 0,
  total numeric(14, 2) not null default 0,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint orders_order_number_not_blank check (length(trim(order_number)) > 0),
  constraint orders_status_allowed check (
    status in ('draft', 'submitted', 'completed', 'cancelled')
  ),
  constraint orders_subtotal_non_negative check (subtotal >= 0),
  constraint orders_total_non_negative check (total >= 0)
);

create unique index orders_company_order_number_active_key
  on public.orders (company_id, order_number)
  where deleted_at is null;

create index orders_company_id_idx on public.orders (company_id)
  where deleted_at is null;
create index orders_branch_id_idx on public.orders (branch_id)
  where deleted_at is null;
create index orders_customer_id_idx on public.orders (customer_id)
  where deleted_at is null;
create index orders_employee_id_idx on public.orders (employee_id)
  where deleted_at is null;
create index orders_company_status_idx on public.orders (company_id, status)
  where deleted_at is null;
create index orders_company_ordered_at_idx on public.orders (company_id, ordered_at desc)
  where deleted_at is null;

create trigger trg_orders_set_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create or replace function public.validate_order_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'orders.branch_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = new.customer_id
      and c.company_id = new.company_id
      and c.deleted_at is null
  ) then
    raise exception 'orders.customer_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.employees e
    where e.id = new.employee_id
      and e.company_id = new.company_id
      and e.deleted_at is null
  ) then
    raise exception 'orders.employee_id must belong to the same company';
  end if;

  return new;
end;
$$;

create trigger trg_orders_validate_tenant_scope
before insert or update of company_id, branch_id, customer_id, employee_id
on public.orders
for each row execute function public.validate_order_tenant_scope();

-- -----------------------------------------------------------------------------
-- order_items
-- -----------------------------------------------------------------------------

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete restrict,
  quantity numeric(14, 3) not null,
  unit_price numeric(14, 2) not null,
  discount numeric(14, 2),
  discount_type text,
  line_total numeric(14, 2) not null,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint order_items_quantity_positive check (quantity > 0),
  constraint order_items_unit_price_non_negative check (unit_price >= 0),
  constraint order_items_line_total_non_negative check (line_total >= 0),
  constraint order_items_discount_non_negative
    check (discount is null or discount >= 0),
  constraint order_items_discount_type_allowed check (
    discount_type is null or discount_type in ('percentage', 'fixed')
  ),
  constraint order_items_discount_pair check (
    (discount is null and discount_type is null)
    or (discount is not null and discount_type is not null)
  ),
  constraint order_items_percentage_discount_range check (
    discount_type is distinct from 'percentage'
    or (discount is not null and discount <= 100)
  )
);

create index order_items_order_id_idx on public.order_items (order_id);
create index order_items_product_id_idx on public.order_items (product_id);
create index order_items_company_id_idx on public.order_items (company_id);

create trigger trg_order_items_set_updated_at
before update on public.order_items
for each row execute function public.set_updated_at();

create or replace function public.validate_order_item_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.orders o
    where o.id = new.order_id
      and o.company_id = new.company_id
      and o.deleted_at is null
  ) then
    raise exception 'order_items.order_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
      and p.deleted_at is null
  ) then
    raise exception 'order_items.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

create trigger trg_order_items_validate_tenant_scope
before insert or update of company_id, order_id, product_id on public.order_items
for each row execute function public.validate_order_item_tenant_scope();

-- -----------------------------------------------------------------------------
-- Comments (audit-friendly documentation)
-- -----------------------------------------------------------------------------

comment on table public.companies is 'Tenant root for each wholesaler/distributor.';
comment on table public.company_settings is 'Branding and localization settings per company.';
comment on table public.branches is 'Company locations used for inventory and order context.';
comment on table public.roles is 'Global system roles for Hub vs Sello access.';
comment on table public.employees is 'Company users linked to Supabase Auth.';
comment on table public.customers is 'B2B customer accounts.';
comment on table public.categories is 'Product categories within a company catalog.';
comment on table public.products is 'Sellable SKUs.';
comment on table public.product_images is 'Product image assets (storage paths).';
comment on table public.inventory is 'Stock quantity of a product at a branch.';
comment on table public.orders is 'Sales order headers.';
comment on table public.order_items is 'Sales order line items with price snapshots.';

comment on column public.roles.display_order is 'UI sort order for role pickers and admin lists.';
comment on column public.company_settings.locale is 'BCP 47 locale for formatting (e.g. en-US).';
comment on column public.products.cost_price is 'Unit cost for future margin, valuation, and purchasing.';
comment on column public.products.selling_price is 'Current catalog selling price.';
comment on column public.inventory.quantity is 'On-hand stock quantity at the branch (Phase 1).';
comment on column public.order_items.unit_price is 'Price snapshot at time of order.';
comment on column public.order_items.discount_type is 'percentage or fixed; must pair with discount.';
comment on column public.orders.status is 'draft | submitted | completed | cancelled';
comment on column public.orders.signature_storage_path is 'Optional customer signature asset path.';
comment on column public.employees.user_id is 'Supabase auth.users id for login/session resolution.';
