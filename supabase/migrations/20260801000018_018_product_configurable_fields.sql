-- =============================================================================
-- 018 — Configurable product fields (tenant-specific specifications)
--
-- Core commerce columns stay on products (name, sku, prices, category…).
-- Industry specs live in products.attributes (jsonb).
-- Companies enable fields via company_product_fields against a seeded catalog.
-- =============================================================================

alter table public.products
  add column if not exists attributes jsonb not null default '{}'::jsonb;

comment on column public.products.attributes is
  'Tenant-configured product specifications keyed by product_field_definitions.key.';

create index if not exists products_attributes_gin_idx
  on public.products using gin (attributes jsonb_path_ops);

-- -----------------------------------------------------------------------------
-- Global field catalog
-- -----------------------------------------------------------------------------

create table if not exists public.product_field_definitions (
  key text primary key,
  label text not null,
  field_type text not null,
  storage text not null,
  column_name text,
  options jsonb not null default '[]'::jsonb,
  default_enabled boolean not null default false,
  default_required boolean not null default false,
  default_show_in_list boolean not null default false,
  default_show_in_catalog boolean not null default true,
  sort_order integer not null default 100,
  help_text text,
  created_at timestamptz not null default timezone('utc', now()),

  constraint product_field_type_allowed check (
    field_type in ('text', 'multiline', 'number', 'select', 'country', 'date')
  ),
  constraint product_field_storage_allowed check (
    storage in ('column', 'attribute', 'inventory')
  ),
  constraint product_field_column_consistent check (
    (storage = 'column' and column_name is not null)
    or (storage = 'inventory' and column_name is not null)
    or (storage = 'attribute' and column_name is null)
  ),
  constraint product_field_label_not_blank check (length(trim(label)) > 0)
);

comment on table public.product_field_definitions is
  'Catalog of product fields companies may enable. Extensible without ALTER TABLE products.';

insert into public.product_field_definitions (
  key, label, field_type, storage, column_name,
  default_enabled, default_required, default_show_in_list, default_show_in_catalog,
  sort_order, help_text, options
) values
  ('barcode', 'Barcode', 'text', 'column', 'barcode',
   true, false, false, false, 10, 'Optional scanned barcode.', '[]'::jsonb),
  ('brand', 'Brand', 'text', 'column', 'brand',
   true, false, true, true, 20, null, '[]'::jsonb),
  ('unit_label', 'Unit', 'select', 'column', 'unit_label',
   true, false, true, true, 30, null,
   '["piece","pack","box","kg","g","liter","ml","meter","pair","set","dozen","roll"]'::jsonb),
  ('description', 'Description', 'multiline', 'column', 'description',
   true, false, false, true, 40, null, '[]'::jsonb),
  ('reorder_level', 'Reorder level', 'number', 'inventory', 'reorder_level',
   true, false, true, false, 50, 'Stock alert threshold for this product.', '[]'::jsonb),
  ('material', 'Material', 'text', 'attribute', null,
   false, false, true, true, 100, null, '[]'::jsonb),
  ('color', 'Color', 'text', 'attribute', null,
   false, false, true, true, 110, null, '[]'::jsonb),
  ('size', 'Size', 'text', 'attribute', null,
   false, false, true, true, 120, null, '[]'::jsonb),
  ('made_in_country', 'Made in country', 'country', 'attribute', null,
   false, false, false, true, 130, 'ISO country of manufacture.', '[]'::jsonb),
  ('weight', 'Weight', 'text', 'attribute', null,
   false, false, false, true, 140, null, '[]'::jsonb),
  ('voltage', 'Voltage', 'text', 'attribute', null,
   false, false, false, true, 150, null, '[]'::jsonb),
  ('capacity', 'Capacity', 'text', 'attribute', null,
   false, false, false, true, 160, null, '[]'::jsonb),
  ('power', 'Power', 'text', 'attribute', null,
   false, false, false, true, 170, null, '[]'::jsonb),
  ('finish', 'Finish', 'text', 'attribute', null,
   false, false, false, true, 180, null, '[]'::jsonb),
  ('dimensions', 'Dimensions', 'text', 'attribute', null,
   false, false, false, true, 190, null, '[]'::jsonb),
  ('expiry', 'Expiry', 'date', 'attribute', null,
   false, false, false, true, 200, null, '[]'::jsonb)
on conflict (key) do update set
  label = excluded.label,
  field_type = excluded.field_type,
  storage = excluded.storage,
  column_name = excluded.column_name,
  default_enabled = excluded.default_enabled,
  default_required = excluded.default_required,
  default_show_in_list = excluded.default_show_in_list,
  default_show_in_catalog = excluded.default_show_in_catalog,
  sort_order = excluded.sort_order,
  help_text = excluded.help_text,
  options = excluded.options;

-- -----------------------------------------------------------------------------
-- Per-company field configuration
-- -----------------------------------------------------------------------------

create table if not exists public.company_product_fields (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  field_key text not null references public.product_field_definitions (key)
    on delete restrict,
  enabled boolean not null default true,
  required boolean not null default false,
  show_in_list boolean not null default false,
  show_in_catalog boolean not null default true,
  label_override text,
  sort_order integer not null default 100,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (company_id, field_key)
);

create index if not exists company_product_fields_company_idx
  on public.company_product_fields (company_id, enabled, sort_order);

comment on table public.company_product_fields is
  'Which product fields a company uses, and where they appear.';

drop trigger if exists trg_company_product_fields_set_updated_at
  on public.company_product_fields;
create trigger trg_company_product_fields_set_updated_at
before update on public.company_product_fields
for each row execute function public.set_updated_at();

insert into public.company_product_fields (
  company_id,
  field_key,
  enabled,
  required,
  show_in_list,
  show_in_catalog,
  sort_order
)
select
  c.id,
  d.key,
  d.default_enabled,
  d.default_required,
  d.default_show_in_list,
  d.default_show_in_catalog,
  d.sort_order
from public.companies c
cross join public.product_field_definitions d
on conflict (company_id, field_key) do nothing;

create or replace function public.ensure_company_product_fields(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.company_product_fields (
    company_id,
    field_key,
    enabled,
    required,
    show_in_list,
    show_in_catalog,
    sort_order
  )
  select
    p_company_id,
    d.key,
    d.default_enabled,
    d.default_required,
    d.default_show_in_list,
    d.default_show_in_catalog,
    d.sort_order
  from public.product_field_definitions d
  on conflict (company_id, field_key) do nothing;
end;
$$;

revoke all on function public.ensure_company_product_fields(uuid) from public;
grant execute on function public.ensure_company_product_fields(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

alter table public.product_field_definitions enable row level security;
alter table public.company_product_fields enable row level security;

drop policy if exists "product_field_definitions_select_authenticated"
  on public.product_field_definitions;
create policy "product_field_definitions_select_authenticated"
  on public.product_field_definitions
  for select
  to authenticated
  using (true);

drop policy if exists "company_product_fields_select_own"
  on public.company_product_fields;
create policy "company_product_fields_select_own"
  on public.company_product_fields
  for select
  to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "company_product_fields_update_own"
  on public.company_product_fields;
create policy "company_product_fields_update_own"
  on public.company_product_fields
  for update
  to authenticated
  using (company_id = public.current_company_id())
  with check (company_id = public.current_company_id());

drop policy if exists "company_product_fields_insert_own"
  on public.company_product_fields;
create policy "company_product_fields_insert_own"
  on public.company_product_fields
  for insert
  to authenticated
  with check (company_id = public.current_company_id());
