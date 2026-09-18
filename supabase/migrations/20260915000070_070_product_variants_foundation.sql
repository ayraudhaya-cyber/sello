-- =============================================================================
-- 070 — Product variants foundation (Phase A)
--
-- Empty sellable-unit table under products. No backfill. No changes to
-- products, inventory, stock_movements, order_items, or RPCs.
--
-- Approved model:
--   products.sku     = parent/catalog/family code (unchanged)
--   product_variants = sellable unit (sku, barcode, price, cost; stock later)
-- =============================================================================

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  label text,
  options jsonb not null default '{}'::jsonb,
  sku text not null,
  barcode text,
  selling_price numeric(14, 2) not null default 0,
  unit_cost numeric(14, 2) not null default 0,
  sort_order integer not null default 0,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint product_variants_sku_not_blank
    check (length(trim(sku)) > 0),
  constraint product_variants_barcode_not_blank
    check (barcode is null or length(trim(barcode)) > 0),
  constraint product_variants_label_not_blank
    check (label is null or length(trim(label)) > 0),
  constraint product_variants_selling_price_non_negative
    check (selling_price >= 0),
  constraint product_variants_unit_cost_non_negative
    check (unit_cost >= 0),
  constraint product_variants_options_object
    check (jsonb_typeof(options) = 'object')
);

comment on table public.product_variants is
  'Sellable units under a parent product. Phase A foundation only — empty until '
  'default-variant backfill (Phase B). Parent products.sku remains the family code; '
  'variant sku is the sellable code. Inventory/order_items attach in later phases.';

comment on column public.product_variants.label is
  'Customer/Rep-facing variant name (e.g. 12"). Null/empty for the hidden default '
  'sellable of a simple product — never display the word Default in UX.';

comment on column public.product_variants.options is
  'Flexible option map for future dimensions (size, color, …). Not auto-filled '
  'from products.attributes.';

comment on column public.product_variants.sku is
  'Sellable SKU. Company-unique among non-deleted variants. May equal products.sku '
  'for the default/simple sellable (separate table uniqueness).';

comment on column public.product_variants.barcode is
  'Optional sellable barcode. Unique among non-deleted variants when set.';

comment on column public.product_variants.is_default is
  'Deterministic target for legacy draft mapping. At most one non-deleted default '
  'per product; retained when the default row evolves into the first real variant.';

comment on column public.product_variants.unit_cost is
  'Variant cost. Hub visibility follows existing can_view_product_cost rules in '
  'later application/RPC work — this column is not masked at the table layer.';

-- Sellable SKU unique per company (active / non-deleted), mirrors products pattern.
create unique index if not exists product_variants_company_sku_active_key
  on public.product_variants (company_id, sku)
  where deleted_at is null;

-- Optional barcode unique per company when set.
create unique index if not exists product_variants_company_barcode_active_key
  on public.product_variants (company_id, barcode)
  where barcode is not null and deleted_at is null;

-- At most one default variant per product among non-deleted rows.
create unique index if not exists product_variants_one_default_per_product_key
  on public.product_variants (product_id)
  where is_default = true and deleted_at is null;

create index if not exists product_variants_company_product_idx
  on public.product_variants (company_id, product_id)
  where deleted_at is null;

create index if not exists product_variants_product_active_idx
  on public.product_variants (product_id)
  where is_active = true and deleted_at is null;

create index if not exists product_variants_company_id_idx
  on public.product_variants (company_id)
  where deleted_at is null;

create index if not exists product_variants_product_sort_idx
  on public.product_variants (product_id, sort_order)
  where deleted_at is null;

drop trigger if exists trg_product_variants_set_updated_at
  on public.product_variants;
create trigger trg_product_variants_set_updated_at
before update on public.product_variants
for each row execute function public.set_updated_at();

-- Tenant integrity: product must belong to the same company.
-- Allows soft-deleted parents (Phase B backfills archived products too).
create or replace function public.validate_product_variant_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
  ) then
    raise exception
      'product_variants.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_product_variants_validate_tenant_scope
  on public.product_variants;
create trigger trg_product_variants_validate_tenant_scope
before insert or update of company_id, product_id
on public.product_variants
for each row execute function public.validate_product_variant_tenant_scope();

alter table public.product_variants enable row level security;

drop policy if exists "product_variants_select_own_company"
  on public.product_variants;
create policy "product_variants_select_own_company"
  on public.product_variants
  for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  );

drop policy if exists "product_variants_insert_own_company"
  on public.product_variants;
create policy "product_variants_insert_own_company"
  on public.product_variants
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
  );

drop policy if exists "product_variants_update_own_company"
  on public.product_variants;
create policy "product_variants_update_own_company"
  on public.product_variants
  for update
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  )
  with check (
    company_id = public.current_company_id()
  );

-- Soft-archive via deleted_at update only (no hard DELETE policy), matching products.
revoke all on table public.product_variants from anon;
grant select, insert, update on table public.product_variants to authenticated;
