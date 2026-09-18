-- =============================================================================
-- 072 — Product variants Phase C: attach inventory + stock_movements
--
-- Adds variant_id to inventory and stock_movements, backfills from each row's
-- product_id → that product's non-deleted is_default variant, then enforces
-- NOT NULL and switches inventory uniqueness to (company_id, branch_id, variant_id).
--
-- Does NOT modify quantities, product_id, RPCs, order_items, or products.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Guards — fail before any schema/data change
-- ---------------------------------------------------------------------------

do $guard$
declare
  missing_defaults integer;
  multi_defaults integer;
  unmappable_inventory integer;
  unmappable_movements integer;
  would_duplicate integer;
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
      'Phase C aborted: % product(s) lack a non-deleted default variant',
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
      'Phase C aborted: % product(s) have multiple non-deleted defaults',
      multi_defaults;
  end if;

  select count(*)::int into unmappable_inventory
  from public.inventory i
  where not exists (
    select 1
    from public.product_variants v
    where v.product_id = i.product_id
      and v.company_id = i.company_id
      and v.is_default = true
      and v.deleted_at is null
  );

  if unmappable_inventory > 0 then
    raise exception
      'Phase C aborted: % inventory row(s) cannot map to a same-company default variant',
      unmappable_inventory;
  end if;

  select count(*)::int into unmappable_movements
  from public.stock_movements m
  where not exists (
    select 1
    from public.product_variants v
    where v.product_id = m.product_id
      and v.company_id = m.company_id
      and v.is_default = true
      and v.deleted_at is null
  );

  if unmappable_movements > 0 then
    raise exception
      'Phase C aborted: % stock_movement row(s) cannot map to a same-company default variant',
      unmappable_movements;
  end if;

  -- Would the new unique key collide?
  select count(*)::int into would_duplicate
  from (
    select i.company_id, i.branch_id, v.id as variant_id
    from public.inventory i
    join public.product_variants v
      on v.product_id = i.product_id
     and v.company_id = i.company_id
     and v.is_default = true
     and v.deleted_at is null
    group by i.company_id, i.branch_id, v.id
    having count(*) > 1
  ) d;

  if would_duplicate > 0 then
    raise exception
      'Phase C aborted: mapping would create % duplicate (company, branch, variant) inventory groups',
      would_duplicate;
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------------
-- inventory.variant_id
-- ---------------------------------------------------------------------------

alter table public.inventory
  add column if not exists variant_id uuid;

comment on column public.inventory.variant_id is
  'Sellable unit stock identity. product_id remains the parent/catalog reference.';

update public.inventory i
set variant_id = v.id
from public.product_variants v
where v.product_id = i.product_id
  and v.company_id = i.company_id
  and v.is_default = true
  and v.deleted_at is null
  and i.variant_id is null;

do $inv_check$
declare
  nulls integer;
  bad_product integer;
  bad_company integer;
begin
  select count(*)::int into nulls
  from public.inventory
  where variant_id is null;

  if nulls > 0 then
    raise exception
      'Phase C aborted: % inventory row(s) still have null variant_id after backfill',
      nulls;
  end if;

  select count(*)::int into bad_product
  from public.inventory i
  join public.product_variants v on v.id = i.variant_id
  where v.product_id is distinct from i.product_id;

  if bad_product > 0 then
    raise exception
      'Phase C aborted: % inventory row(s) have variant_id for a different product_id',
      bad_product;
  end if;

  select count(*)::int into bad_company
  from public.inventory i
  join public.product_variants v on v.id = i.variant_id
  where v.company_id is distinct from i.company_id;

  if bad_company > 0 then
    raise exception
      'Phase C aborted: % inventory row(s) have cross-tenant variant_id',
      bad_company;
  end if;
end;
$inv_check$;

alter table public.inventory
  alter column variant_id set not null;

alter table public.inventory
  drop constraint if exists inventory_variant_id_fkey;

alter table public.inventory
  add constraint inventory_variant_id_fkey
  foreign key (variant_id) references public.product_variants (id)
  on delete restrict;

-- Variant-level uniqueness (sellable identity).
-- Keep inventory_company_branch_product_key until Phase E rewrites
-- adjust_inventory ON CONFLICT (company_id, branch_id, product_id). Dropping it
-- now would break live stock adjustments while RPCs remain product-keyed.
alter table public.inventory
  drop constraint if exists inventory_company_branch_variant_key;

alter table public.inventory
  add constraint inventory_company_branch_variant_key
  unique (company_id, branch_id, variant_id);

comment on constraint inventory_company_branch_variant_key on public.inventory is
  'Phase C sellable uniqueness. Product-level unique retained temporarily for '
  'adjust_inventory ON CONFLICT until Phase E.';

create index if not exists inventory_variant_id_idx
  on public.inventory (variant_id);

create index if not exists inventory_company_variant_idx
  on public.inventory (company_id, variant_id);

-- ---------------------------------------------------------------------------
-- stock_movements.variant_id
-- ---------------------------------------------------------------------------

alter table public.stock_movements
  add column if not exists variant_id uuid;

comment on column public.stock_movements.variant_id is
  'Sellable unit for this ledger row. product_id remains the parent/catalog reference. '
  'Historical quantity_delta / quantity_after / type / references are unchanged.';

update public.stock_movements m
set variant_id = v.id
from public.product_variants v
where v.product_id = m.product_id
  and v.company_id = m.company_id
  and v.is_default = true
  and v.deleted_at is null
  and m.variant_id is null;

do $sm_check$
declare
  nulls integer;
  bad_product integer;
  bad_company integer;
begin
  select count(*)::int into nulls
  from public.stock_movements
  where variant_id is null;

  if nulls > 0 then
    raise exception
      'Phase C aborted: % stock_movement row(s) still have null variant_id after backfill',
      nulls;
  end if;

  select count(*)::int into bad_product
  from public.stock_movements m
  join public.product_variants v on v.id = m.variant_id
  where v.product_id is distinct from m.product_id;

  if bad_product > 0 then
    raise exception
      'Phase C aborted: % stock_movement row(s) have variant_id for a different product_id',
      bad_product;
  end if;

  select count(*)::int into bad_company
  from public.stock_movements m
  join public.product_variants v on v.id = m.variant_id
  where v.company_id is distinct from m.company_id;

  if bad_company > 0 then
    raise exception
      'Phase C aborted: % stock_movement row(s) have cross-tenant variant_id',
      bad_company;
  end if;
end;
$sm_check$;

alter table public.stock_movements
  alter column variant_id set not null;

alter table public.stock_movements
  drop constraint if exists stock_movements_variant_id_fkey;

alter table public.stock_movements
  add constraint stock_movements_variant_id_fkey
  foreign key (variant_id) references public.product_variants (id)
  on delete restrict;

-- Access-pattern index only (no uniqueness change on the ledger).
create index if not exists stock_movements_branch_variant_idx
  on public.stock_movements (company_id, branch_id, variant_id, created_at desc);

create index if not exists stock_movements_variant_created_at_idx
  on public.stock_movements (company_id, variant_id, created_at desc);
