-- =============================================================================
-- 073 — Product variants Phase D: order_items variant_id + historical snapshots
--
-- Attaches every order_item to its product's non-deleted default variant and
-- stores product_name / variant_label / sku snapshots for stable documents.
-- Does NOT change quantities, prices, discounts, fulfillment fields, RPCs,
-- inventory, stock_movements, products, or Flutter.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

do $guard$
declare
  missing_defaults integer;
  multi_defaults integer;
  unmappable integer;
begin
  select count(*)::int into missing_defaults
  from public.products p
  where not exists (
    select 1
    from public.product_variants v
    where v.product_id = p.id
      and v.is_default = true
      and v.deleted_at is null
  );

  if missing_defaults > 0 then
    raise exception
      'Phase D aborted: % product(s) lack a non-deleted default variant',
      missing_defaults;
  end if;

  select count(*)::int into multi_defaults
  from (
    select product_id
    from public.product_variants
    where is_default = true
      and deleted_at is null
    group by product_id
    having count(*) > 1
  ) d;

  if multi_defaults > 0 then
    raise exception
      'Phase D aborted: % product(s) have multiple non-deleted defaults',
      multi_defaults;
  end if;

  select count(*)::int into unmappable
  from public.order_items oi
  where not exists (
    select 1
    from public.product_variants v
    where v.product_id = oi.product_id
      and v.company_id = oi.company_id
      and v.is_default = true
      and v.deleted_at is null
  );

  if unmappable > 0 then
    raise exception
      'Phase D aborted: % order_item row(s) cannot map to a same-company default variant',
      unmappable;
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.order_items
  add column if not exists variant_id uuid;

alter table public.order_items
  add column if not exists product_name text;

alter table public.order_items
  add column if not exists variant_label text;

alter table public.order_items
  add column if not exists sku text;

comment on column public.order_items.variant_id is
  'Sellable unit for this line. product_id remains the parent/catalog reference.';

comment on column public.order_items.product_name is
  'Historical product name snapshot at write/migration time. Not updated on rename.';

comment on column public.order_items.variant_label is
  'Historical variant label snapshot (null for simple/default sellables). '
  'Not updated on later label changes.';

comment on column public.order_items.sku is
  'Historical sellable SKU snapshot. Not updated on later SKU changes.';

-- Preserve updated_at / avoid set_updated_at side-effects during backfill.
alter table public.order_items
  disable trigger trg_order_items_set_updated_at;

update public.order_items oi
set
  variant_id = v.id,
  product_name = p.name,
  variant_label = v.label,
  sku = v.sku
from public.product_variants v
join public.products p
  on p.id = v.product_id
where v.product_id = oi.product_id
  and v.company_id = oi.company_id
  and v.is_default = true
  and v.deleted_at is null
  and oi.variant_id is null;

alter table public.order_items
  enable trigger trg_order_items_set_updated_at;

do $verify$
declare
  null_variant integer;
  null_name integer;
  null_sku integer;
  bad_product integer;
  bad_company integer;
  not_default integer;
  name_mismatch integer;
  label_mismatch integer;
  sku_mismatch integer;
begin
  select count(*)::int into null_variant
  from public.order_items where variant_id is null;

  if null_variant > 0 then
    raise exception
      'Phase D aborted: % order_item row(s) still have null variant_id',
      null_variant;
  end if;

  select count(*)::int into null_name
  from public.order_items
  where product_name is null or length(trim(product_name)) = 0;

  if null_name > 0 then
    raise exception
      'Phase D aborted: % order_item row(s) have blank product_name snapshot',
      null_name;
  end if;

  select count(*)::int into null_sku
  from public.order_items
  where sku is null or length(trim(sku)) = 0;

  if null_sku > 0 then
    raise exception
      'Phase D aborted: % order_item row(s) have blank sku snapshot',
      null_sku;
  end if;

  select count(*)::int into bad_product
  from public.order_items oi
  join public.product_variants v on v.id = oi.variant_id
  where v.product_id is distinct from oi.product_id;

  if bad_product > 0 then
    raise exception
      'Phase D aborted: % order_item row(s) map to a different product_id',
      bad_product;
  end if;

  select count(*)::int into bad_company
  from public.order_items oi
  join public.product_variants v on v.id = oi.variant_id
  where v.company_id is distinct from oi.company_id;

  if bad_company > 0 then
    raise exception
      'Phase D aborted: % order_item row(s) have cross-tenant variant_id',
      bad_company;
  end if;

  select count(*)::int into not_default
  from public.order_items oi
  join public.product_variants v on v.id = oi.variant_id
  where not (v.is_default = true and v.deleted_at is null);

  if not_default > 0 then
    raise exception
      'Phase D aborted: % order_item row(s) do not map to a live default variant',
      not_default;
  end if;

  select count(*)::int into name_mismatch
  from public.order_items oi
  join public.products p on p.id = oi.product_id
  where oi.product_name is distinct from p.name;

  if name_mismatch > 0 then
    raise exception
      'Phase D aborted: % order_item product_name snapshot(s) mismatch products.name',
      name_mismatch;
  end if;

  select count(*)::int into label_mismatch
  from public.order_items oi
  join public.product_variants v on v.id = oi.variant_id
  where oi.variant_label is distinct from v.label;

  if label_mismatch > 0 then
    raise exception
      'Phase D aborted: % order_item variant_label snapshot(s) mismatch variant.label',
      label_mismatch;
  end if;

  select count(*)::int into sku_mismatch
  from public.order_items oi
  join public.product_variants v on v.id = oi.variant_id
  where oi.sku is distinct from v.sku;

  if sku_mismatch > 0 then
    raise exception
      'Phase D aborted: % order_item sku snapshot(s) mismatch variant.sku',
      sku_mismatch;
  end if;
end;
$verify$;

alter table public.order_items
  alter column variant_id set not null;

alter table public.order_items
  alter column product_name set not null;

alter table public.order_items
  alter column sku set not null;

-- variant_label remains nullable (simple/default sellables have null labels).

alter table public.order_items
  drop constraint if exists order_items_product_name_not_blank;

alter table public.order_items
  add constraint order_items_product_name_not_blank
  check (length(trim(product_name)) > 0);

alter table public.order_items
  drop constraint if exists order_items_sku_not_blank;

alter table public.order_items
  add constraint order_items_sku_not_blank
  check (length(trim(sku)) > 0);

alter table public.order_items
  drop constraint if exists order_items_variant_label_not_blank;

alter table public.order_items
  add constraint order_items_variant_label_not_blank
  check (variant_label is null or length(trim(variant_label)) > 0);

alter table public.order_items
  drop constraint if exists order_items_variant_id_fkey;

alter table public.order_items
  add constraint order_items_variant_id_fkey
  foreign key (variant_id) references public.product_variants (id)
  on delete restrict;

create index if not exists order_items_variant_id_idx
  on public.order_items (variant_id);

create index if not exists order_items_company_variant_idx
  on public.order_items (company_id, variant_id);
