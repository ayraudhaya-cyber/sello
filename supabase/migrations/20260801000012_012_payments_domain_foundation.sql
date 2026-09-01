-- =============================================================================
-- Migration 012 — Payments domain foundation
--
-- Financial ledger for collections against customer receivables / orders.
-- Refunds: status + columns only (full reverse RPC deferred).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- payments (header)
-- ---------------------------------------------------------------------------

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete restrict,
  employee_id uuid not null references public.employees (id) on delete restrict,
  payment_number text not null,
  amount numeric(14, 2) not null,
  method text not null,
  status text not null default 'completed',
  reference text,
  notes text,
  received_at timestamptz not null default timezone('utc', now()),
  refunded_at timestamptz,
  cancelled_at timestamptz,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,

  constraint payments_payment_number_not_blank
    check (length(trim(payment_number)) > 0),
  constraint payments_amount_positive check (amount > 0),
  constraint payments_method_allowed check (
    method in ('cash', 'card', 'bank_transfer', 'wallet', 'credit_settlement')
  ),
  constraint payments_status_allowed check (
    status in ('completed', 'pending', 'refunded', 'cancelled')
  ),
  constraint payments_reference_not_blank
    check (reference is null or length(trim(reference)) > 0),
  constraint payments_notes_not_blank
    check (notes is null or length(trim(notes)) > 0)
);

create unique index if not exists payments_company_number_active_key
  on public.payments (company_id, payment_number)
  where deleted_at is null;

create index if not exists payments_company_received_at_idx
  on public.payments (company_id, received_at desc)
  where deleted_at is null;

create index if not exists payments_company_customer_idx
  on public.payments (company_id, customer_id)
  where deleted_at is null;

create index if not exists payments_company_status_idx
  on public.payments (company_id, status)
  where deleted_at is null;

create index if not exists payments_company_method_idx
  on public.payments (company_id, method)
  where deleted_at is null;

create trigger trg_payments_set_updated_at
before update on public.payments
for each row execute function public.set_updated_at();

create or replace function public.validate_payment_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.branches b
    where b.id = new.branch_id
      and b.company_id = new.company_id
      and b.deleted_at is null
  ) then
    raise exception 'payments.branch_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = new.customer_id
      and c.company_id = new.company_id
      and c.deleted_at is null
  ) then
    raise exception 'payments.customer_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.employees e
    where e.id = new.employee_id
      and e.company_id = new.company_id
      and e.deleted_at is null
  ) then
    raise exception 'payments.employee_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_payments_validate_tenant_scope on public.payments;
create trigger trg_payments_validate_tenant_scope
before insert or update of company_id, branch_id, customer_id, employee_id
on public.payments
for each row execute function public.validate_payment_tenant_scope();

comment on table public.payments is
  'Customer collection / settlement header. Orders.payment_* is sale intent; this is the ledger.';
comment on column public.payments.method is
  'cash | card | bank_transfer | wallet | credit_settlement';
comment on column public.payments.status is
  'completed | pending | refunded | cancelled — refunds Phase 1 mark status only.';

-- ---------------------------------------------------------------------------
-- payment_allocations (order linkage)
-- ---------------------------------------------------------------------------

create table if not exists public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  payment_id uuid not null references public.payments (id) on delete cascade,
  order_id uuid not null references public.orders (id) on delete restrict,
  amount numeric(14, 2) not null,
  created_by uuid references public.employees (id) on delete set null,
  updated_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),

  constraint payment_allocations_amount_positive check (amount > 0),
  constraint payment_allocations_payment_order_key unique (payment_id, order_id)
);

create index if not exists payment_allocations_payment_id_idx
  on public.payment_allocations (payment_id);

create index if not exists payment_allocations_order_id_idx
  on public.payment_allocations (order_id);

create index if not exists payment_allocations_company_id_idx
  on public.payment_allocations (company_id);

create trigger trg_payment_allocations_set_updated_at
before update on public.payment_allocations
for each row execute function public.set_updated_at();

create or replace function public.validate_payment_allocation_tenant_scope()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.payments p
    where p.id = new.payment_id
      and p.company_id = new.company_id
      and p.deleted_at is null
  ) then
    raise exception 'payment_allocations.payment_id must belong to the same company';
  end if;

  if not exists (
    select 1 from public.orders o
    where o.id = new.order_id
      and o.company_id = new.company_id
      and o.deleted_at is null
  ) then
    raise exception 'payment_allocations.order_id must belong to the same company';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_payment_allocations_validate_tenant_scope
  on public.payment_allocations;
create trigger trg_payment_allocations_validate_tenant_scope
before insert or update of company_id, payment_id, order_id
on public.payment_allocations
for each row execute function public.validate_payment_allocation_tenant_scope();

comment on table public.payment_allocations is
  'Links a payment to one or more orders (full / partial / multi-payment).';

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.next_payment_number(p_company_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  seq bigint;
  stamp text := to_char(timezone('utc', now()), 'YYYYMMDD');
begin
  if p_company_id is distinct from public.current_company_id() then
    raise exception 'Forbidden';
  end if;

  select count(*) + 1
    into seq
  from public.payments
  where company_id = p_company_id
    and received_at::date = timezone('utc', now())::date;

  return 'PAY-' || stamp || '-' || lpad(seq::text, 4, '0');
end;
$$;

revoke all on function public.next_payment_number(uuid) from public;
grant execute on function public.next_payment_number(uuid) to authenticated;

create or replace function public.refresh_order_payment_status(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o_total numeric(14, 2);
  allocated numeric(14, 2);
begin
  select total into o_total
  from public.orders
  where id = p_order_id
    and deleted_at is null;

  if o_total is null then
    return;
  end if;

  select coalesce(sum(pa.amount), 0)
    into allocated
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = p_order_id
    and p.deleted_at is null
    and p.status = 'completed';

  update public.orders
  set payment_status = case
    when allocated <= 0 then 'unpaid'
    when allocated + 0.001 >= o_total then 'paid'
    else 'partial'
  end
  where id = p_order_id;
end;
$$;

revoke all on function public.refresh_order_payment_status(uuid) from public;
grant execute on function public.refresh_order_payment_status(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- receive_payment
-- p_allocations: jsonb [{ "order_id": "...", "amount": 12.50 }, ...]
-- ---------------------------------------------------------------------------

create or replace function public.receive_payment(
  p_customer_id uuid,
  p_amount numeric,
  p_method text,
  p_allocations jsonb default '[]'::jsonb,
  p_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  branch uuid;
  payment_id uuid;
  payment_no text;
  alloc jsonb;
  alloc_order uuid;
  alloc_amount numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  customer_row public.customers%rowtype;
  order_row public.orders%rowtype;
  already_paid numeric(14, 2);
  remaining numeric(14, 2);
  ar_reduction numeric(14, 2);
  overpay numeric(14, 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  if p_method not in ('cash', 'card', 'bank_transfer', 'wallet', 'credit_settlement') then
    raise exception 'Unsupported payment method.';
  end if;

  select * into customer_row
  from public.customers
  where id = p_customer_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Customer not found.';
  end if;

  select e.branch_id into branch
  from public.employees e
  where e.id = emp
    and e.company_id = company
    and e.deleted_at is null;

  if branch is null then
    select b.id into branch
    from public.branches b
    where b.company_id = company
      and b.deleted_at is null
      and b.is_active = true
    order by b.created_at
    limit 1;
  end if;

  if branch is null then
    raise exception 'No branch available for this payment.';
  end if;

  if p_method = 'wallet' and customer_row.wallet_balance < p_amount then
    raise exception 'Insufficient wallet balance.';
  end if;

  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_order := (alloc->>'order_id')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    if alloc_amount is null or alloc_amount <= 0 then
      raise exception 'Allocation amount must be positive.';
    end if;

    select * into order_row
    from public.orders
    where id = alloc_order
      and company_id = company
      and customer_id = p_customer_id
      and deleted_at is null
      and status = 'completed';

    if not found then
      raise exception 'Allocation order is not a completed order for this customer.';
    end if;

    select coalesce(sum(pa.amount), 0)
      into already_paid
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = alloc_order
      and p.deleted_at is null
      and p.status = 'completed';

    remaining := order_row.total - already_paid;
    if alloc_amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on order %', order_row.order_number;
    end if;

    alloc_total := alloc_total + alloc_amount;
  end loop;

  if alloc_total > p_amount + 0.001 then
    raise exception 'Allocations exceed payment amount.';
  end if;

  payment_no := public.next_payment_number(company);

  insert into public.payments (
    company_id,
    branch_id,
    customer_id,
    employee_id,
    payment_number,
    amount,
    method,
    status,
    reference,
    notes,
    created_by,
    updated_by
  )
  values (
    company,
    branch,
    p_customer_id,
    emp,
    payment_no,
    p_amount,
    p_method,
    'completed',
    nullif(trim(coalesce(p_reference, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    emp,
    emp
  )
  returning id into payment_id;

  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_order := (alloc->>'order_id')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    insert into public.payment_allocations (
      company_id,
      payment_id,
      order_id,
      amount,
      created_by,
      updated_by
    )
    values (
      company,
      payment_id,
      alloc_order,
      alloc_amount,
      emp,
      emp
    );

    perform public.refresh_order_payment_status(alloc_order);
  end loop;

  -- Apply to customer financial profile
  ar_reduction := least(p_amount, customer_row.current_balance);
  overpay := greatest(p_amount - alloc_total, 0);

  if p_method = 'wallet' then
    update public.customers
    set
      wallet_balance = wallet_balance - p_amount,
      current_balance = greatest(current_balance - alloc_total, 0),
      updated_by = emp
    where id = p_customer_id;
  else
    update public.customers
    set
      current_balance = greatest(current_balance - ar_reduction, 0),
      wallet_balance = wallet_balance + overpay,
      updated_by = emp
    where id = p_customer_id;
  end if;

  return payment_id;
end;
$$;

revoke all on function public.receive_payment(uuid, numeric, text, jsonb, text, text) from public;
grant execute on function public.receive_payment(uuid, numeric, text, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- mark_payment_refunded — architecture only (no balance reverse yet)
-- ---------------------------------------------------------------------------

create or replace function public.mark_payment_refunded(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  p public.payments%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into p
  from public.payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if p.status <> 'completed' then
    raise exception 'Only completed payments can be marked refunded.';
  end if;

  update public.payments
  set
    status = 'refunded',
    refunded_at = timezone('utc', now()),
    updated_by = emp
  where id = p_payment_id;

  -- Intentionally does not reverse customer balances or order allocations yet.
end;
$$;

revoke all on function public.mark_payment_refunded(uuid) from public;
grant execute on function public.mark_payment_refunded(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.payments enable row level security;
alter table public.payment_allocations enable row level security;

drop policy if exists "payments_select_own_company" on public.payments;
create policy "payments_select_own_company"
  on public.payments
  for select
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

drop policy if exists "payments_insert_own_company" on public.payments;
create policy "payments_insert_own_company"
  on public.payments
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

drop policy if exists "payments_update_own_company" on public.payments;
create policy "payments_update_own_company"
  on public.payments
  for update
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null)
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );

drop policy if exists "payment_allocations_select_own_company"
  on public.payment_allocations;
create policy "payment_allocations_select_own_company"
  on public.payment_allocations
  for select
  to authenticated
  using (company_id = public.current_company_id());

drop policy if exists "payment_allocations_insert_own_company"
  on public.payment_allocations;
create policy "payment_allocations_insert_own_company"
  on public.payment_allocations
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );
