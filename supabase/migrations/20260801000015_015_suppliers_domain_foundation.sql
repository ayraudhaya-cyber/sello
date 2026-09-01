-- =============================================================================
-- Migration 015 — Suppliers domain foundation
--
-- Procurement directory for Hub. Prepares shared identity for future Purchase
-- Orders, GRN, supplier payments, and product sourcing — without implementing
-- those flows yet.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- suppliers
-- ---------------------------------------------------------------------------

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid references public.branches (id) on delete set null,
  code text,
  name text not null,
  contact_name text,
  phone text,
  whatsapp text,
  email text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  postal_code text,
  country text,
  tax_number text,
  category text,
  payment_terms text,
  bank_name text,
  bank_account text,
  notes text,
  credit_limit numeric(14, 2) not null default 0,
  opening_balance numeric(14, 2) not null default 0,
  current_balance numeric(14, 2) not null default 0,
  last_purchase_at timestamptz,
  lead_time_days integer,
  is_active boolean not null default true,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint suppliers_name_not_blank check (length(trim(name)) > 0),
  constraint suppliers_code_not_blank
    check (code is null or length(trim(code)) > 0),
  constraint suppliers_contact_name_not_blank
    check (contact_name is null or length(trim(contact_name)) > 0),
  constraint suppliers_phone_not_blank
    check (phone is null or length(trim(phone)) > 0),
  constraint suppliers_whatsapp_not_blank
    check (whatsapp is null or length(trim(whatsapp)) > 0),
  constraint suppliers_email_format
    check (
      email is null
      or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    ),
  constraint suppliers_category_not_blank
    check (category is null or length(trim(category)) > 0),
  constraint suppliers_payment_terms_not_blank
    check (payment_terms is null or length(trim(payment_terms)) > 0),
  constraint suppliers_tax_number_not_blank
    check (tax_number is null or length(trim(tax_number)) > 0),
  constraint suppliers_credit_limit_non_negative check (credit_limit >= 0),
  constraint suppliers_opening_balance_finite
    check (opening_balance = opening_balance),
  constraint suppliers_current_balance_finite
    check (current_balance = current_balance),
  constraint suppliers_lead_time_non_negative
    check (lead_time_days is null or lead_time_days >= 0)
);

create unique index if not exists suppliers_company_code_active_key
  on public.suppliers (company_id, code)
  where code is not null and deleted_at is null;

create index if not exists suppliers_company_id_idx
  on public.suppliers (company_id)
  where deleted_at is null;

create index if not exists suppliers_company_active_idx
  on public.suppliers (company_id, is_active)
  where deleted_at is null;

create index if not exists suppliers_company_updated_at_idx
  on public.suppliers (company_id, updated_at desc)
  where deleted_at is null;

create index if not exists suppliers_company_name_idx
  on public.suppliers (company_id, name)
  where deleted_at is null;

create index if not exists suppliers_company_category_idx
  on public.suppliers (company_id, category)
  where category is not null and deleted_at is null;

drop trigger if exists trg_suppliers_set_updated_at on public.suppliers;
create trigger trg_suppliers_set_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

create or replace function public.validate_supplier_branch_company()
returns trigger
language plpgsql
as $$
begin
  if new.branch_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'suppliers.branch_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_suppliers_validate_branch_company on public.suppliers;
create trigger trg_suppliers_validate_branch_company
before insert or update of branch_id, company_id on public.suppliers
for each row execute function public.validate_supplier_branch_company();

comment on table public.suppliers is
  'Procurement vendors. Foundation for future POs, GRN, and supplier payments.';
comment on column public.suppliers.current_balance is
  'Outstanding payable balance (ledger-driven when supplier payments ship).';
comment on column public.suppliers.opening_balance is
  'Opening payable when the supplier was onboarded.';
comment on column public.suppliers.last_purchase_at is
  'Last PO / receipt timestamp — populated by future procurement flows.';
comment on column public.suppliers.lead_time_days is
  'Typical lead time for sourcing / PO planning (future).';
comment on column public.suppliers.category is
  'Optional supplier category label (filter-ready; taxonomy later).';
comment on column public.suppliers.payment_terms is
  'Human-readable terms e.g. Net 30, COD.';

-- ---------------------------------------------------------------------------
-- Product sourcing seam (nullable preferred supplier)
-- ---------------------------------------------------------------------------

alter table public.products
  add column if not exists preferred_supplier_id uuid
    references public.suppliers (id) on delete set null;

create index if not exists products_preferred_supplier_idx
  on public.products (preferred_supplier_id)
  where preferred_supplier_id is not null and deleted_at is null;

create or replace function public.validate_product_preferred_supplier_company()
returns trigger
language plpgsql
as $$
begin
  if new.preferred_supplier_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.suppliers s
    where s.id = new.preferred_supplier_id
      and s.company_id = new.company_id
      and s.deleted_at is null
  ) then
    raise exception
      'products.preferred_supplier_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_products_validate_preferred_supplier
  on public.products;
create trigger trg_products_validate_preferred_supplier
before insert or update of preferred_supplier_id, company_id
on public.products
for each row execute function public.validate_product_preferred_supplier_company();

comment on column public.products.preferred_supplier_id is
  'Optional preferred vendor for sourcing / PO suggestions (UI later).';

-- ---------------------------------------------------------------------------
-- Future procurement notes (no tables yet)
-- ---------------------------------------------------------------------------
-- purchase_orders / purchase_order_items → supplier_id, inventory receipt via GRN
-- goods_received_notes → stock_movements purchase_in
-- supplier_payments / allocations → reduce suppliers.current_balance
-- Sello Intelligence: delay rate, avg delivery, spend concentration

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.suppliers enable row level security;

drop policy if exists "suppliers_select_own_company" on public.suppliers;
create policy "suppliers_select_own_company"
  on public.suppliers
  for select
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

drop policy if exists "suppliers_insert_own_company" on public.suppliers;
create policy "suppliers_insert_own_company"
  on public.suppliers
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

drop policy if exists "suppliers_update_own_company" on public.suppliers;
create policy "suppliers_update_own_company"
  on public.suppliers
  for update
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null)
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );
