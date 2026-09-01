-- =============================================================================
-- 025 — Product Details intelligence (groups, types, industry catalog)
--
-- Extends 018 without schema churn on products.attributes.
-- Description stays a standard column field; hidden from Settings toggles.
-- =============================================================================

-- Expand allowed input types
alter table public.product_field_definitions
  drop constraint if exists product_field_type_allowed;

alter table public.product_field_definitions
  add constraint product_field_type_allowed check (
    field_type in (
      'text', 'multiline', 'number', 'select', 'country', 'date',
      'colour', 'currency', 'barcode', 'boolean'
    )
  );

alter table public.product_field_definitions
  add column if not exists group_key text not null default 'common';

alter table public.product_field_definitions
  add column if not exists settings_visible boolean not null default true;

comment on column public.product_field_definitions.group_key is
  'Suggested detail group: common | hardware | stationery | electrical | furniture | grocery | pharmacy | clothing | other.';
comment on column public.product_field_definitions.settings_visible is
  'When false, field is a standard product column (e.g. description) not shown in Product Details settings.';

alter table public.product_field_definitions
  drop constraint if exists product_field_group_allowed;

alter table public.product_field_definitions
  add constraint product_field_group_allowed check (
    group_key in (
      'common', 'hardware', 'stationery', 'electrical',
      'furniture', 'grocery', 'pharmacy', 'clothing', 'other'
    )
  );

-- Company can customise dropdown values without changing the global catalog
alter table public.company_product_fields
  add column if not exists options_override jsonb;

comment on column public.company_product_fields.options_override is
  'Optional company-specific dropdown values. Null = use definition.options.';

-- Refresh / extend catalog
insert into public.product_field_definitions (
  key, label, field_type, storage, column_name,
  default_enabled, default_required, default_show_in_list, default_show_in_catalog,
  sort_order, help_text, options, group_key, settings_visible
) values
  -- Common
  ('barcode', 'Barcode', 'barcode', 'column', 'barcode',
   true, false, false, false, 10, 'Scan or type a product barcode.', '[]'::jsonb, 'common', true),
  ('brand', 'Brand', 'text', 'column', 'brand',
   true, false, true, true, 20, null, '[]'::jsonb, 'common', true),
  ('unit_label', 'Unit', 'select', 'column', 'unit_label',
   true, false, true, true, 30, null,
   '["piece","pack","box","kg","g","liter","ml","meter","pair","set","dozen","roll"]'::jsonb,
   'common', true),
  ('item_code', 'Item Code', 'text', 'attribute', null,
   false, false, true, true, 35, 'Internal or supplier item code.', '[]'::jsonb, 'common', true),
  ('description', 'Description', 'multiline', 'column', 'description',
   true, false, false, true, 40, 'Standard product notes — always available on the product form.',
   '[]'::jsonb, 'common', false),
  ('made_in_country', 'Made In Country', 'country', 'attribute', null,
   false, false, false, true, 45, 'Country of manufacture.', '[]'::jsonb, 'common', true),
  ('reorder_level', 'Reorder level', 'number', 'inventory', 'reorder_level',
   true, false, true, false, 50, 'Stock alert threshold for this product.', '[]'::jsonb, 'common', true),

  -- Hardware
  ('material', 'Material', 'select', 'attribute', null,
   false, false, true, true, 100, null,
   '["Steel","Brass","Plastic","Aluminium","Wood","Iron","Copper","Glass"]'::jsonb,
   'hardware', true),
  ('color', 'Colour', 'colour', 'attribute', null,
   false, false, true, true, 110, null, '[]'::jsonb, 'hardware', true),
  ('size', 'Size', 'text', 'attribute', null,
   false, false, true, true, 120, null, '[]'::jsonb, 'hardware', true),
  ('finish', 'Finish', 'text', 'attribute', null,
   false, false, false, true, 180, null, '[]'::jsonb, 'hardware', true),
  ('dimensions', 'Dimensions', 'text', 'attribute', null,
   false, false, false, true, 190, null, '[]'::jsonb, 'hardware', true),
  ('weight', 'Weight', 'text', 'attribute', null,
   false, false, false, true, 140, null, '[]'::jsonb, 'hardware', true),

  -- Stationery
  ('book_type', 'Book Type', 'select', 'attribute', null,
   false, false, true, true, 210, null,
   '["Exercise Book","Notebook","Register","Drawing Book","Sketch Pad"]'::jsonb,
   'stationery', true),
  ('ruling', 'Ruling', 'select', 'attribute', null,
   false, false, true, true, 220, null,
   '["Single Rule","Double Rule","Four Square","Plain","Graph"]'::jsonb,
   'stationery', true),
  ('pages', 'Pages', 'number', 'attribute', null,
   false, false, true, true, 230, null, '[]'::jsonb, 'stationery', true),
  ('book_size', 'Book Size', 'select', 'attribute', null,
   false, false, true, true, 240, null,
   '["A4","A5","A6","B5","Letter"]'::jsonb,
   'stationery', true),
  ('cover', 'Cover', 'select', 'attribute', null,
   false, false, false, true, 250, null,
   '["Soft Cover","Hard Cover","Spiral","Paperback"]'::jsonb,
   'stationery', true),

  -- Electrical
  ('voltage', 'Voltage', 'text', 'attribute', null,
   false, false, false, true, 150, null, '[]'::jsonb, 'electrical', true),
  ('capacity', 'Capacity', 'text', 'attribute', null,
   false, false, false, true, 160, null, '[]'::jsonb, 'electrical', true),
  ('power', 'Power', 'text', 'attribute', null,
   false, false, false, true, 170, null, '[]'::jsonb, 'electrical', true),
  ('wattage', 'Wattage', 'text', 'attribute', null,
   false, false, false, true, 175, null, '[]'::jsonb, 'electrical', true),

  -- Furniture
  ('furniture_material', 'Frame / Material', 'select', 'attribute', null,
   false, false, true, true, 260, null,
   '["Wood","Metal","Glass","Rattan","MDF","Particle Board"]'::jsonb,
   'furniture', true),
  ('seating_capacity', 'Seating Capacity', 'number', 'attribute', null,
   false, false, true, true, 270, null, '[]'::jsonb, 'furniture', true),

  -- Grocery
  ('pack_size', 'Pack Size', 'text', 'attribute', null,
   false, false, true, true, 280, null, '[]'::jsonb, 'grocery', true),
  ('expiry', 'Expiry', 'date', 'attribute', null,
   false, false, false, true, 200, null, '[]'::jsonb, 'grocery', true),
  ('net_weight', 'Net Weight', 'text', 'attribute', null,
   false, false, true, true, 290, null, '[]'::jsonb, 'grocery', true),

  -- Pharmacy
  ('dosage', 'Dosage', 'text', 'attribute', null,
   false, false, true, true, 300, null, '[]'::jsonb, 'pharmacy', true),
  ('active_ingredient', 'Active Ingredient', 'text', 'attribute', null,
   false, false, false, true, 310, null, '[]'::jsonb, 'pharmacy', true),
  ('prescription_required', 'Prescription Required', 'boolean', 'attribute', null,
   false, false, true, true, 320, null, '[]'::jsonb, 'pharmacy', true),

  -- Clothing
  ('clothing_size', 'Clothing Size', 'select', 'attribute', null,
   false, false, true, true, 330, null,
   '["XS","S","M","L","XL","XXL","XXXL"]'::jsonb,
   'clothing', true),
  ('clothing_colour', 'Colour', 'colour', 'attribute', null,
   false, false, true, true, 340, null, '[]'::jsonb, 'clothing', true),
  ('fabric', 'Fabric', 'select', 'attribute', null,
   false, false, true, true, 350, null,
   '["Cotton","Polyester","Linen","Silk","Denim","Wool","Blend"]'::jsonb,
   'clothing', true),
  ('gender', 'Gender', 'select', 'attribute', null,
   false, false, true, true, 360, null,
   '["Men","Women","Unisex","Kids"]'::jsonb,
   'clothing', true)
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
  options = excluded.options,
  group_key = excluded.group_key,
  settings_visible = excluded.settings_visible;

-- Ensure every company has rows for new keys
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

-- Keep ensure RPC current for onboarding / late companies
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
