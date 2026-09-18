-- =============================================================================
-- 071 — Product variants Phase B: default-variant backfill
--
-- Inserts exactly one is_default variant per existing product (active and
-- soft-deleted). Copies sku/barcode/price/cost. Does NOT touch products,
-- inventory, stock_movements, order_items, or RPCs.
--
-- Idempotent: skips products that already have any product_variants row.
-- =============================================================================

-- Fail loudly if a non-deleted product already has a default (should not happen
-- before this backfill, but guards against partial/manual inserts).
do $guard$
declare
  conflict_count integer;
begin
  select count(*)::int into conflict_count
  from (
    select product_id
    from public.product_variants
    where is_default = true
      and deleted_at is null
    group by product_id
    having count(*) > 1
  ) d;

  if conflict_count > 0 then
    raise exception
      'Phase B aborted: % product(s) already have multiple non-deleted defaults',
      conflict_count;
  end if;
end;
$guard$;

insert into public.product_variants (
  company_id,
  product_id,
  label,
  options,
  sku,
  barcode,
  selling_price,
  unit_cost,
  sort_order,
  is_default,
  is_active,
  created_by,
  updated_by,
  created_at,
  updated_at,
  deleted_at
)
select
  p.company_id,
  p.id,
  null,
  '{}'::jsonb,
  p.sku,
  p.barcode,
  p.selling_price,
  p.unit_cost,
  0,
  true,
  p.is_active,
  p.created_by,
  p.updated_by,
  timezone('utc', now()),
  timezone('utc', now()),
  p.deleted_at
from public.products p
where not exists (
  select 1
  from public.product_variants v
  where v.product_id = p.id
);

comment on table public.product_variants is
  'Sellable units under a parent product. Phase B: every product has one '
  'is_default variant mirroring its sellable state. Inventory/order_items '
  'attachment is later phases.';
