-- 111 — Stock rows for sellable options that never received one.
--
-- Creating a product with options, or a save that stopped after the product
-- row was written, could leave product_variants with no inventory row. Hub
-- Inventory only lists inventory, so those products stayed invisible and
-- search could not find them.
--
-- Inserts quantity 0 for every non-deleted variant at every live branch.
-- Existing stock is not changed (ON CONFLICT DO NOTHING).
-- Non-default options are inserted first. A default option is inserted only
-- when that product does not already have a default stock row, so the
-- one-default-row rule cannot abort the whole statement.

insert into public.inventory (
  company_id,
  branch_id,
  product_id,
  variant_id,
  quantity,
  is_default_variant
)
select
  v.company_id,
  b.id,
  v.product_id,
  v.id,
  0,
  false
from public.product_variants v
join public.branches b
  on b.company_id = v.company_id
 and b.deleted_at is null
where v.deleted_at is null
  and coalesce(v.is_default, false) = false
  and not exists (
    select 1
    from public.inventory i
    where i.company_id = v.company_id
      and i.branch_id = b.id
      and i.variant_id = v.id
  )
on conflict (company_id, branch_id, variant_id) do nothing;

insert into public.inventory (
  company_id,
  branch_id,
  product_id,
  variant_id,
  quantity,
  is_default_variant
)
select
  v.company_id,
  b.id,
  v.product_id,
  v.id,
  0,
  true
from public.product_variants v
join public.branches b
  on b.company_id = v.company_id
 and b.deleted_at is null
where v.deleted_at is null
  and v.is_default = true
  and not exists (
    select 1
    from public.inventory i
    where i.company_id = v.company_id
      and i.branch_id = b.id
      and i.variant_id = v.id
  )
  and not exists (
    select 1
    from public.inventory i
    where i.company_id = v.company_id
      and i.branch_id = b.id
      and i.product_id = v.product_id
      and i.is_default_variant
  )
on conflict (company_id, branch_id, variant_id) do nothing;
