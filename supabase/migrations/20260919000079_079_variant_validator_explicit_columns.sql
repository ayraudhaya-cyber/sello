-- =============================================================================
-- 079 — Fix INVOKER variant validators after 075 unit_cost column lock
--
-- Symptom: Hub multi-option save fails with
--   "permission denied for table product_variants"
-- when inventory upsert fires trg_inventory_validate_tenant_scope.
--
-- Cause: validate_inventory_tenant_scope / validate_stock_movement_tenant_scope
-- used SELECT * INTO product_variants%rowtype. After 075, authenticated cannot
-- SELECT unit_cost, so whole-row reads fail. Explicit API selects (no unit_cost)
-- still work.
--
-- Fix: keep SECURITY INVOKER; select only columns required for validation.
-- Does NOT change grants, RLS, triggers, or Flutter.
-- =============================================================================

create or replace function public.validate_inventory_tenant_scope()
returns trigger
language plpgsql
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

  -- Flutter may insert product_id without variant_id (pre-Phase F).
  if new.variant_id is null then
    if new.product_id is null then
      raise exception 'inventory requires product_id or variant_id';
    end if;
    -- resolve_default_product_variant is SECURITY DEFINER; project only the
    -- fields this validator needs (never unit_cost).
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
  'BEFORE INSERT/UPDATE inventory tenant checks. Reads only '
  'product_variants.company_id / product_id / is_default (and id via '
  'resolve_default_product_variant) so authenticated INVOKER sessions work '
  'after 075 locked unit_cost.';

create or replace function public.validate_stock_movement_tenant_scope()
returns trigger
language plpgsql
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
  'BEFORE INSERT/UPDATE stock_movements tenant checks. Reads only '
  'product_variants.company_id / product_id so authenticated INVOKER sessions '
  'work after 075 locked unit_cost.';
