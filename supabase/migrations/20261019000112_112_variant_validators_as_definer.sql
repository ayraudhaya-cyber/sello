-- 112 — Variant saves fail with "permission denied for table product_variants"
--
-- Adding or editing a sellable option writes an inventory row. The BEFORE
-- INSERT trigger on inventory reads product_variants as the signed-in user.
-- Migration 075 removed table-level SELECT so unit_cost stays hidden, and a
-- whole-row read (SELECT * or a product_variants row type) is denied.
--
-- Run the same checks as the database owner, and only read the columns the
-- check needs. Cost stays unreadable by the API. Company matching is unchanged.

create or replace function public.validate_inventory_tenant_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_product_id uuid;
  v_is_default boolean;
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

  if new.variant_id is null then
    if new.product_id is null then
      raise exception 'inventory requires product_id or variant_id';
    end if;
    select d.id, d.product_id, d.is_default
      into new.variant_id, v_product_id, v_is_default
    from public.resolve_default_product_variant(new.company_id, new.product_id) as d;
    new.product_id := v_product_id;
    new.is_default_variant := v_is_default;
  else
    select v.company_id, v.product_id, v.is_default
      into v_company_id, v_product_id, v_is_default
    from public.product_variants v
    where v.id = new.variant_id;

    if not found then
      raise exception 'inventory.variant_id not found';
    end if;

    if v_company_id is distinct from new.company_id then
      raise exception 'inventory.variant_id must belong to the same company';
    end if;

    if new.product_id is null then
      new.product_id := v_product_id;
    elsif v_product_id is distinct from new.product_id then
      raise exception 'inventory.variant_id does not belong to inventory.product_id';
    end if;

    new.is_default_variant := coalesce(v_is_default, false);
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
  ) then
    raise exception 'inventory.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

comment on function public.validate_inventory_tenant_scope() is
  'BEFORE INSERT/UPDATE inventory tenant checks. SECURITY DEFINER so the '
  'unit_cost column lock cannot reject a variant save. Still enforces company match.';

create or replace function public.validate_stock_movement_tenant_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_product_id uuid;
begin
  if not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'stock_movements.branch_id must belong to the same company';
  end if;

  if new.variant_id is null then
    raise exception 'stock_movements.variant_id is required';
  end if;

  select v.company_id, v.product_id
    into v_company_id, v_product_id
  from public.product_variants v
  where v.id = new.variant_id;

  if not found then
    raise exception 'stock_movements.variant_id not found';
  end if;

  if v_company_id is distinct from new.company_id then
    raise exception 'stock_movements.variant_id must belong to the same company';
  end if;

  if new.product_id is null then
    new.product_id := v_product_id;
  elsif v_product_id is distinct from new.product_id then
    raise exception
      'stock_movements.variant_id does not belong to stock_movements.product_id';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
  ) then
    raise exception 'stock_movements.product_id must belong to the same company';
  end if;

  return new;
end;
$$;

comment on function public.validate_stock_movement_tenant_scope() is
  'BEFORE INSERT/UPDATE stock_movements tenant checks. SECURITY DEFINER so the '
  'unit_cost column lock cannot reject the write. Still enforces company match.';

revoke all on function public.validate_inventory_tenant_scope() from public;
revoke all on function public.validate_stock_movement_tenant_scope() from public;
