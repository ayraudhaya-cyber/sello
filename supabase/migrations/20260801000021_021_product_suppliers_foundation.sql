-- =============================================================================
-- 021 — Supplier ↔ product sourcing foundation
--
-- Preferred supplier remains products.preferred_supplier_id (Hub V1 UX).
-- product_suppliers prepares multiple suppliers per product (is_primary,
-- lead_time, MOQ) for Purchase Orders / GRN without changing today's UX.
-- =============================================================================

create table if not exists public.product_suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete cascade,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  is_primary boolean not null default false,
  lead_time_days integer,
  min_order_quantity numeric(14, 3),
  notes text,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint product_suppliers_lead_time_non_negative
    check (lead_time_days is null or lead_time_days >= 0),
  constraint product_suppliers_moq_non_negative
    check (min_order_quantity is null or min_order_quantity >= 0),
  constraint product_suppliers_notes_not_blank
    check (notes is null or length(trim(notes)) > 0)
);

create unique index if not exists product_suppliers_product_supplier_active_key
  on public.product_suppliers (product_id, supplier_id)
  where deleted_at is null;

create unique index if not exists product_suppliers_one_primary_per_product
  on public.product_suppliers (product_id)
  where is_primary = true and deleted_at is null;

create index if not exists product_suppliers_company_supplier_idx
  on public.product_suppliers (company_id, supplier_id)
  where deleted_at is null;

create index if not exists product_suppliers_company_product_idx
  on public.product_suppliers (company_id, product_id)
  where deleted_at is null;

comment on table public.product_suppliers is
  'Multi-supplier sourcing foundation. Hub V1 still uses products.preferred_supplier_id as the primary link.';

drop trigger if exists trg_product_suppliers_set_updated_at
  on public.product_suppliers;
create trigger trg_product_suppliers_set_updated_at
before update on public.product_suppliers
for each row execute function public.set_updated_at();

create or replace function public.validate_product_supplier_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.products p
    where p.id = new.product_id
      and p.company_id = new.company_id
      and p.deleted_at is null
  ) then
    raise exception 'product_suppliers.product_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.suppliers s
    where s.id = new.supplier_id
      and s.company_id = new.company_id
      and s.deleted_at is null
  ) then
    raise exception 'product_suppliers.supplier_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_product_suppliers_validate_tenant_scope
  on public.product_suppliers;
create trigger trg_product_suppliers_validate_tenant_scope
before insert or update of company_id, product_id, supplier_id
on public.product_suppliers
for each row execute function public.validate_product_supplier_tenant_scope();

-- Keep junction primary row aligned when preferred_supplier_id changes.
create or replace function public.sync_product_preferred_supplier_link()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_id uuid;
begin
  if new.preferred_supplier_id is null then
    update public.product_suppliers
    set
      is_primary = false,
      updated_at = timezone('utc', now())
    where product_id = new.id
      and is_primary = true
      and deleted_at is null;
    return new;
  end if;

  select ps.id into existing_id
  from public.product_suppliers ps
  where ps.product_id = new.id
    and ps.supplier_id = new.preferred_supplier_id
    and ps.deleted_at is null
  limit 1;

  if existing_id is null then
    insert into public.product_suppliers (
      company_id,
      product_id,
      supplier_id,
      is_primary
    ) values (
      new.company_id,
      new.id,
      new.preferred_supplier_id,
      true
    );
  else
    update public.product_suppliers
    set
      is_primary = true,
      updated_at = timezone('utc', now())
    where id = existing_id;
  end if;

  update public.product_suppliers
  set
    is_primary = false,
    updated_at = timezone('utc', now())
  where product_id = new.id
    and supplier_id is distinct from new.preferred_supplier_id
    and is_primary = true
    and deleted_at is null;

  return new;
end;
$$;

drop trigger if exists trg_products_sync_preferred_supplier_link on public.products;
create trigger trg_products_sync_preferred_supplier_link
after insert or update of preferred_supplier_id, company_id
on public.products
for each row execute function public.sync_product_preferred_supplier_link();

alter table public.product_suppliers enable row level security;

drop policy if exists "product_suppliers_select_own_company"
  on public.product_suppliers;
create policy "product_suppliers_select_own_company"
  on public.product_suppliers
  for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  );

drop policy if exists "product_suppliers_insert_own_company"
  on public.product_suppliers;
create policy "product_suppliers_insert_own_company"
  on public.product_suppliers
  for insert
  to authenticated
  with check (company_id = public.current_company_id());

drop policy if exists "product_suppliers_update_own_company"
  on public.product_suppliers;
create policy "product_suppliers_update_own_company"
  on public.product_suppliers
  for update
  to authenticated
  using (
    company_id = public.current_company_id()
    and deleted_at is null
  )
  with check (company_id = public.current_company_id());

-- Backfill primary links from existing preferred_supplier_id.
insert into public.product_suppliers (
  company_id,
  product_id,
  supplier_id,
  is_primary
)
select
  p.company_id,
  p.id,
  p.preferred_supplier_id,
  true
from public.products p
where p.preferred_supplier_id is not null
  and p.deleted_at is null
  and not exists (
    select 1
    from public.product_suppliers ps
    where ps.product_id = p.id
      and ps.supplier_id = p.preferred_supplier_id
      and ps.deleted_at is null
  );
