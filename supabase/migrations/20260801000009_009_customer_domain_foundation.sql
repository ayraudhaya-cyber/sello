-- =============================================================================
-- Migration 009 — Customer domain foundation
--
-- Extends public.customers for Hub Customers Phase 1 and enables RLS.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.customers
  add column if not exists customer_type text not null default 'retail';

alter table public.customers
  add column if not exists whatsapp text;

alter table public.customers
  add column if not exists company_name text;

alter table public.customers
  add column if not exists tax_number text;

alter table public.customers
  add column if not exists credit_allowed boolean not null default false;

alter table public.customers
  add column if not exists opening_balance numeric(14, 2) not null default 0;

alter table public.customers
  add column if not exists wallet_balance numeric(14, 2) not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'customers_customer_type_allowed'
  ) then
    alter table public.customers
      add constraint customers_customer_type_allowed
        check (customer_type in ('retail', 'wholesale'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'customers_whatsapp_not_blank'
  ) then
    alter table public.customers
      add constraint customers_whatsapp_not_blank
        check (whatsapp is null or length(trim(whatsapp)) > 0);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'customers_company_name_not_blank'
  ) then
    alter table public.customers
      add constraint customers_company_name_not_blank
        check (company_name is null or length(trim(company_name)) > 0);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'customers_tax_number_not_blank'
  ) then
    alter table public.customers
      add constraint customers_tax_number_not_blank
        check (tax_number is null or length(trim(tax_number)) > 0);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'customers_opening_balance_finite'
  ) then
    alter table public.customers
      add constraint customers_opening_balance_finite
        check (opening_balance = opening_balance);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'customers_wallet_balance_non_negative'
  ) then
    alter table public.customers
      add constraint customers_wallet_balance_non_negative
        check (wallet_balance >= 0);
  end if;
end $$;

create index if not exists customers_company_type_idx
  on public.customers (company_id, customer_type)
  where deleted_at is null;

create index if not exists customers_company_updated_at_idx
  on public.customers (company_id, updated_at desc)
  where deleted_at is null;

create index if not exists customers_company_phone_idx
  on public.customers (company_id, phone)
  where phone is not null and deleted_at is null;

comment on column public.customers.customer_type is
  'retail | wholesale — Phase 1 customer classification.';
comment on column public.customers.current_balance is
  'Outstanding receivable balance (stored; ledger-driven later).';
comment on column public.customers.wallet_balance is
  'Customer wallet credit available for sales (Phase 1 seed).';
comment on column public.customers.opening_balance is
  'Opening outstanding balance when the customer was onboarded.';
comment on column public.customers.credit_allowed is
  'Whether the customer may purchase on credit.';

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.customers enable row level security;

drop policy if exists "customers_select_own_company" on public.customers;
create policy "customers_select_own_company"
  on public.customers
  for select
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

drop policy if exists "customers_insert_own_company" on public.customers;
create policy "customers_insert_own_company"
  on public.customers
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

drop policy if exists "customers_update_own_company" on public.customers;
create policy "customers_update_own_company"
  on public.customers
  for update
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null)
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );
