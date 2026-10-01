-- =============================================================================
-- 088 — Opening balance adjustment (post-create historical AR)
--
-- Owner/Manager records money a customer already owed before Sello.
-- Append-only customer_receivable_adjustments is the document.
-- customers.opening_balance / current_balance increment additively.
-- Payments may allocate to an order XOR this adjustment.
-- Create-time opening_balance rows are not backfilled.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Role gate — same Hub financial set as can_auto_apply_collections
-- ---------------------------------------------------------------------------

create or replace function public.can_record_opening_balance_adjustment()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role_code(), '') in (
    'owner',
    'administrator',
    'manager'
  );
$$;

comment on function public.can_record_opening_balance_adjustment() is
  'Owner / Administrator / Manager may record post-create opening AR. '
  'Sales Rep and Sales In-charge cannot.';

revoke all on function public.can_record_opening_balance_adjustment() from public;
grant execute on function public.can_record_opening_balance_adjustment()
  to authenticated;

-- ---------------------------------------------------------------------------
-- customer_receivable_adjustments
-- ---------------------------------------------------------------------------

create table if not exists public.customer_receivable_adjustments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete restrict,
  branch_id uuid references public.branches (id) on delete set null,
  adjustment_number text not null,
  kind text not null default 'opening_balance',
  amount numeric(14, 2) not null,
  recognized_at timestamptz not null,
  notes text,
  created_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),

  constraint customer_receivable_adjustments_number_not_blank
    check (length(trim(adjustment_number)) > 0),
  constraint customer_receivable_adjustments_kind_allowed
    check (kind in ('opening_balance')),
  constraint customer_receivable_adjustments_amount_positive
    check (amount > 0),
  constraint customer_receivable_adjustments_notes_not_blank
    check (notes is null or length(trim(notes)) > 0)
);

create unique index if not exists customer_receivable_adjustments_company_number_key
  on public.customer_receivable_adjustments (company_id, adjustment_number);

create index if not exists customer_receivable_adjustments_customer_idx
  on public.customer_receivable_adjustments (company_id, customer_id, recognized_at);

comment on table public.customer_receivable_adjustments is
  'Append-only receivable documents that are not orders. '
  'kind=opening_balance is historical debt recorded after customer create.';
comment on column public.customer_receivable_adjustments.recognized_at is
  'As-of date for aging and Collections Report. Not rewritten.';

alter table public.customer_receivable_adjustments enable row level security;

drop policy if exists "customer_receivable_adjustments_select_own_company"
  on public.customer_receivable_adjustments;
create policy "customer_receivable_adjustments_select_own_company"
  on public.customer_receivable_adjustments
  for select
  to authenticated
  using (company_id = public.current_company_id());

revoke all on table public.customer_receivable_adjustments from public;
grant select on table public.customer_receivable_adjustments to authenticated;

-- ---------------------------------------------------------------------------
-- payment_allocations: order XOR opening-balance adjustment
-- ---------------------------------------------------------------------------

alter table public.payment_allocations
  alter column order_id drop not null;

alter table public.payment_allocations
  add column if not exists receivable_adjustment_id uuid
    references public.customer_receivable_adjustments (id) on delete restrict;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'payment_allocations_exactly_one_target'
  ) then
    alter table public.payment_allocations
      add constraint payment_allocations_exactly_one_target
        check (
          (order_id is not null and receivable_adjustment_id is null)
          or (order_id is null and receivable_adjustment_id is not null)
        );
  end if;
end $$;

alter table public.payment_allocations
  drop constraint if exists payment_allocations_payment_order_key;

create unique index if not exists payment_allocations_payment_order_uidx
  on public.payment_allocations (payment_id, order_id)
  where order_id is not null;

create unique index if not exists payment_allocations_payment_adjustment_uidx
  on public.payment_allocations (payment_id, receivable_adjustment_id)
  where receivable_adjustment_id is not null;

create index if not exists payment_allocations_adjustment_id_idx
  on public.payment_allocations (receivable_adjustment_id)
  where receivable_adjustment_id is not null;

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

  if new.order_id is not null then
    if not exists (
      select 1 from public.orders o
      where o.id = new.order_id
        and o.company_id = new.company_id
        and o.deleted_at is null
    ) then
      raise exception 'payment_allocations.order_id must belong to the same company';
    end if;
  end if;

  if new.receivable_adjustment_id is not null then
    if not exists (
      select 1
      from public.customer_receivable_adjustments a
      join public.payments p on p.id = new.payment_id
      where a.id = new.receivable_adjustment_id
        and a.company_id = new.company_id
        and a.customer_id = p.customer_id
    ) then
      raise exception
        'payment_allocations.receivable_adjustment_id must belong to the same company and customer';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_payment_allocations_validate_tenant_scope
  on public.payment_allocations;
create trigger trg_payment_allocations_validate_tenant_scope
before insert or update of company_id, payment_id, order_id, receivable_adjustment_id
on public.payment_allocations
for each row execute function public.validate_payment_allocation_tenant_scope();

comment on table public.payment_allocations is
  'Links a payment to one order or one opening-balance adjustment (exactly one).';
comment on column public.payment_allocations.receivable_adjustment_id is
  'Target when collecting against a customer_receivable_adjustments row.';

-- ---------------------------------------------------------------------------
-- Remaining helper (completed allocations only; pending does not reduce)
-- ---------------------------------------------------------------------------

create or replace function public._receivable_allocation_remaining(
  p_company_id uuid,
  p_customer_id uuid,
  p_order_id uuid,
  p_adjustment_id uuid,
  p_exclude_payment_id uuid default null
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  order_row public.orders%rowtype;
  adj_row public.customer_receivable_adjustments%rowtype;
  already_paid numeric(14, 2);
begin
  if (p_order_id is null) = (p_adjustment_id is null) then
    raise exception 'Allocation must target either an order or an opening balance.';
  end if;

  if p_order_id is not null then
    select * into order_row
    from public.orders
    where id = p_order_id
      and company_id = p_company_id
      and customer_id = p_customer_id
      and deleted_at is null
      and status in ('placed', 'partially_delivered', 'completed');

    if not found then
      raise exception
        'Allocation order must be a placed, partially delivered, or completed order for this customer.';
    end if;

    select coalesce(sum(pa.amount), 0)
      into already_paid
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = p_order_id
      and p.deleted_at is null
      and p.status = 'completed'
      and (p_exclude_payment_id is null or p.id <> p_exclude_payment_id);

    return order_row.total - already_paid;
  end if;

  select * into adj_row
  from public.customer_receivable_adjustments
  where id = p_adjustment_id
    and company_id = p_company_id
    and customer_id = p_customer_id
    and kind = 'opening_balance';

  if not found then
    raise exception 'Opening balance adjustment not found for this customer.';
  end if;

  select coalesce(sum(pa.amount), 0)
    into already_paid
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.receivable_adjustment_id = p_adjustment_id
    and p.deleted_at is null
    and p.status = 'completed'
    and (p_exclude_payment_id is null or p.id <> p_exclude_payment_id);

  return adj_row.amount - already_paid;
end;
$$;

revoke all on function public._receivable_allocation_remaining(
  uuid, uuid, uuid, uuid, uuid
) from public;

-- ---------------------------------------------------------------------------
-- receive_payment — accept order_id or receivable_adjustment_id
-- ---------------------------------------------------------------------------

create or replace function public.receive_payment(
  p_customer_id uuid,
  p_amount numeric,
  p_method text,
  p_allocations jsonb default '[]'::jsonb,
  p_reference text default null,
  p_notes text default null,
  p_visit_id uuid default null
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
  alloc_adj uuid;
  alloc_amount numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  customer_row public.customers%rowtype;
  remaining numeric(14, 2);
  approval_required boolean := false;
  payment_status text := 'completed';
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

  if p_visit_id is not null and not exists (
    select 1 from public.customer_visits cv
    where cv.id = p_visit_id
      and cv.company_id = company
      and cv.customer_id = p_customer_id
      and cv.deleted_at is null
  ) then
    raise exception 'Visit not found for this customer.';
  end if;

  select coalesce(cs.collection_approval_required, false)
    into approval_required
  from public.company_settings cs
  where cs.company_id = company
  limit 1;

  if approval_required and not public.can_auto_apply_collections() then
    payment_status := 'pending';
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
    alloc_order := nullif(trim(coalesce(alloc->>'order_id', '')), '')::uuid;
    alloc_adj := nullif(trim(coalesce(alloc->>'receivable_adjustment_id', '')), '')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    if alloc_amount is null or alloc_amount <= 0 then
      raise exception 'Allocation amount must be positive.';
    end if;

    remaining := public._receivable_allocation_remaining(
      company,
      p_customer_id,
      alloc_order,
      alloc_adj,
      null
    );
    if alloc_amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on this receivable.';
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
    visit_id,
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
    payment_status,
    nullif(trim(coalesce(p_reference, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    p_visit_id,
    emp,
    emp
  )
  returning id into payment_id;

  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_order := nullif(trim(coalesce(alloc->>'order_id', '')), '')::uuid;
    alloc_adj := nullif(trim(coalesce(alloc->>'receivable_adjustment_id', '')), '')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    insert into public.payment_allocations (
      company_id,
      payment_id,
      order_id,
      receivable_adjustment_id,
      amount,
      created_by,
      updated_by
    )
    values (
      company,
      payment_id,
      alloc_order,
      alloc_adj,
      alloc_amount,
      emp,
      emp
    );
  end loop;

  if payment_status = 'completed' then
    perform public.apply_payment_financials(payment_id);
  end if;

  return payment_id;
end;
$$;

revoke all on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid
) from public;
grant execute on function public.receive_payment(
  uuid, numeric, text, jsonb, text, text, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- apply_payment_financials — skip order status for adjustment allocations
-- ---------------------------------------------------------------------------

create or replace function public.apply_payment_financials(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  payment_row public.payments%rowtype;
  customer_row public.customers%rowtype;
  alloc_row public.payment_allocations%rowtype;
  remaining numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  ar_reduction numeric(14, 2);
  overpay numeric(14, 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into payment_row
  from public.payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  select * into customer_row
  from public.customers
  where id = payment_row.customer_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Customer not found.';
  end if;

  if payment_row.method = 'wallet'
     and customer_row.wallet_balance < payment_row.amount then
    raise exception 'Insufficient wallet balance.';
  end if;

  for alloc_row in
    select *
    from public.payment_allocations
    where payment_id = p_payment_id
  loop
    remaining := public._receivable_allocation_remaining(
      company,
      payment_row.customer_id,
      alloc_row.order_id,
      alloc_row.receivable_adjustment_id,
      p_payment_id
    );
    if alloc_row.amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on this receivable.';
    end if;
    alloc_total := alloc_total + alloc_row.amount;
  end loop;

  ar_reduction := least(payment_row.amount, customer_row.current_balance);
  overpay := greatest(payment_row.amount - alloc_total, 0);

  if payment_row.method = 'wallet' then
    update public.customers
    set
      wallet_balance = wallet_balance - payment_row.amount,
      current_balance = greatest(current_balance - alloc_total, 0),
      updated_by = emp
    where id = payment_row.customer_id;
  else
    update public.customers
    set
      current_balance = greatest(current_balance - ar_reduction, 0),
      wallet_balance = wallet_balance + overpay,
      updated_by = emp
    where id = payment_row.customer_id;
  end if;

  for alloc_row in
    select *
    from public.payment_allocations
    where payment_id = p_payment_id
  loop
    if alloc_row.order_id is not null then
      perform public.refresh_order_payment_status(alloc_row.order_id);
    end if;
  end loop;
end;
$$;

revoke all on function public.apply_payment_financials(uuid) from public;
grant execute on function public.apply_payment_financials(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Cheque allocations — same XOR target as receive_payment
-- ---------------------------------------------------------------------------

create or replace function public._insert_cheque_allocations(
  p_payment_id uuid,
  p_company_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_allocations jsonb,
  p_emp uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  alloc jsonb;
  alloc_order uuid;
  alloc_adj uuid;
  alloc_amount numeric(14, 2);
  alloc_total numeric(14, 2) := 0;
  remaining numeric(14, 2);
begin
  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_order := nullif(trim(coalesce(alloc->>'order_id', '')), '')::uuid;
    alloc_adj := nullif(trim(coalesce(alloc->>'receivable_adjustment_id', '')), '')::uuid;
    alloc_amount := (alloc->>'amount')::numeric;

    if alloc_amount is null or alloc_amount <= 0 then
      raise exception 'Allocation amount must be positive.';
    end if;

    remaining := public._receivable_allocation_remaining(
      p_company_id,
      p_customer_id,
      alloc_order,
      alloc_adj,
      null
    );
    if alloc_amount > remaining + 0.001 then
      raise exception 'Allocation exceeds remaining balance on this receivable.';
    end if;

    alloc_total := alloc_total + alloc_amount;

    insert into public.payment_allocations (
      company_id,
      payment_id,
      order_id,
      receivable_adjustment_id,
      amount,
      created_by,
      updated_by
    )
    values (
      p_company_id,
      p_payment_id,
      alloc_order,
      alloc_adj,
      alloc_amount,
      p_emp,
      p_emp
    );
  end loop;

  if alloc_total > p_amount + 0.001 then
    raise exception 'Allocations exceed cheque amount.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Numbering
-- ---------------------------------------------------------------------------

create or replace function public.next_opening_balance_number(p_company_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  day_key text := to_char(timezone('utc', now()), 'YYYYMMDD');
  seq int;
begin
  if p_company_id is distinct from public.current_company_id() then
    raise exception 'Forbidden';
  end if;

  select coalesce(max(
    nullif(
      substring(adjustment_number from 'OB-' || day_key || '-([0-9]+)$'),
      ''
    )::int
  ), 0) + 1
  into seq
  from public.customer_receivable_adjustments
  where company_id = p_company_id
    and adjustment_number like 'OB-' || day_key || '-%';

  return 'OB-' || day_key || '-' || lpad(seq::text, 4, '0');
end;
$$;

revoke all on function public.next_opening_balance_number(uuid) from public;
grant execute on function public.next_opening_balance_number(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- record_opening_balance_adjustment
-- ---------------------------------------------------------------------------

create or replace function public.record_opening_balance_adjustment(
  p_customer_id uuid,
  p_amount numeric,
  p_notes text default null,
  p_recognized_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  customer_row public.customers%rowtype;
  branch uuid;
  adj_id uuid;
  adj_no text;
  amount_value numeric(14, 2);
  recognized timestamptz;
  currency_code text;
  money_label text;
  summary_text text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_record_opening_balance_adjustment() then
    raise exception 'Only Owner or Manager can add an opening balance.';
  end if;

  amount_value := round(coalesce(p_amount, 0)::numeric, 2);
  if amount_value <= 0 then
    raise exception 'Opening balance amount must be greater than zero.';
  end if;

  recognized := coalesce(p_recognized_at, timezone('utc', now()));
  if recognized > timezone('utc', now()) + interval '1 day' then
    raise exception 'As-of date cannot be in the future.';
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

  if not coalesce(customer_row.is_active, false) then
    raise exception 'Customer is inactive.';
  end if;

  branch := customer_row.branch_id;
  if branch is null then
    select e.branch_id into branch
    from public.employees e
    where e.id = emp
      and e.company_id = company
      and e.deleted_at is null;
  end if;
  if branch is null then
    select b.id into branch
    from public.branches b
    where b.company_id = company
      and b.deleted_at is null
      and b.is_active = true
    order by b.created_at
    limit 1;
  end if;

  adj_no := public.next_opening_balance_number(company);

  insert into public.customer_receivable_adjustments (
    company_id,
    customer_id,
    branch_id,
    adjustment_number,
    kind,
    amount,
    recognized_at,
    notes,
    created_by
  )
  values (
    company,
    p_customer_id,
    branch,
    adj_no,
    'opening_balance',
    amount_value,
    recognized,
    nullif(trim(coalesce(p_notes, '')), ''),
    emp
  )
  returning id into adj_id;

  update public.customers
  set
    opening_balance = opening_balance + amount_value,
    current_balance = current_balance + amount_value,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_customer_id
    and company_id = company;

  select coalesce(cs.currency, 'USD')
    into currency_code
  from public.company_settings cs
  where cs.company_id = company
  limit 1;

  money_label := case upper(coalesce(currency_code, 'USD'))
    when 'LKR' then 'Rs '
    when 'USD' then '$'
    when 'EUR' then E'€'
    when 'GBP' then E'£'
    else coalesce(currency_code, '') || ' '
  end;

  summary_text :=
    'Opening balance of '
    || money_label
    || to_char(amount_value, 'FM999999999990.00')
    || ' added for '
    || customer_row.name;

  perform public.log_company_activity(
    company,
    'customers',
    'opening_balance_added',
    summary_text,
    emp,
    null,
    'customer',
    p_customer_id,
    jsonb_build_object(
      'adjustment_id', adj_id,
      'adjustment_number', adj_no,
      'amount', amount_value
    )
  );

  return adj_id;
end;
$$;

comment on function public.record_opening_balance_adjustment(
  uuid, numeric, text, timestamptz
) is
  'Owner/Manager additive opening AR after customer create. Does not create an order.';

revoke all on function public.record_opening_balance_adjustment(
  uuid, numeric, text, timestamptz
) from public;
grant execute on function public.record_opening_balance_adjustment(
  uuid, numeric, text, timestamptz
) to authenticated;

-- ---------------------------------------------------------------------------
-- Collections Report — UNION opening-balance documents
-- ---------------------------------------------------------------------------

drop function if exists public.fetch_collections_report(timestamptz, uuid[]);

create or replace function public.fetch_collections_report(
  p_as_of timestamptz,
  p_employee_ids uuid[] default null
)
returns table (
  order_id uuid,
  order_number text,
  ordered_at timestamptz,
  customer_id uuid,
  customer_name text,
  customer_phone text,
  employee_id uuid,
  employee_name text,
  order_total numeric,
  amount_paid numeric,
  open_balance numeric,
  document_type text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  company uuid := public.current_company_id();
  filter_reps boolean :=
    p_employee_ids is not null and cardinality(p_employee_ids) > 0;
begin
  if company is null then
    raise exception 'Session context missing.';
  end if;

  return query
    with paid_orders as (
      select
        pa.order_id,
        coalesce(sum(pa.amount), 0)::numeric(14, 2) as amount_paid
      from public.payment_allocations pa
      inner join public.payments p on p.id = pa.payment_id
      where p.company_id = company
        and p.status = 'completed'
        and p.deleted_at is null
        and p.received_at <= p_as_of
        and pa.order_id is not null
      group by pa.order_id
    ),
    paid_adjustments as (
      select
        pa.receivable_adjustment_id,
        coalesce(sum(pa.amount), 0)::numeric(14, 2) as amount_paid
      from public.payment_allocations pa
      inner join public.payments p on p.id = pa.payment_id
      where p.company_id = company
        and p.status = 'completed'
        and p.deleted_at is null
        and p.received_at <= p_as_of
        and pa.receivable_adjustment_id is not null
      group by pa.receivable_adjustment_id
    )
    select
      o.id,
      o.order_number,
      o.ordered_at,
      c.id,
      c.name,
      nullif(trim(c.phone), ''),
      o.employee_id,
      e.full_name,
      o.total,
      coalesce(paid_orders.amount_paid, 0)::numeric(14, 2),
      (o.total - coalesce(paid_orders.amount_paid, 0))::numeric(14, 2),
      'Invoice'::text
    from public.orders o
    inner join public.customers c on c.id = o.customer_id
    left join public.employees e on e.id = o.employee_id
    left join paid_orders on paid_orders.order_id = o.id
    where o.company_id = company
      and o.deleted_at is null
      and o.status in ('placed', 'partially_delivered', 'completed')
      and o.ordered_at <= p_as_of
      and (
        not filter_reps
        or o.employee_id = any (p_employee_ids)
      )
      and (o.total - coalesce(paid_orders.amount_paid, 0)) > 0.001

    union all

    select
      a.id,
      a.adjustment_number,
      a.recognized_at,
      c.id,
      c.name,
      nullif(trim(c.phone), ''),
      null::uuid,
      '—'::text,
      a.amount,
      coalesce(paid_adjustments.amount_paid, 0)::numeric(14, 2),
      (a.amount - coalesce(paid_adjustments.amount_paid, 0))::numeric(14, 2),
      'Opening balance'::text
    from public.customer_receivable_adjustments a
    inner join public.customers c on c.id = a.customer_id
    left join paid_adjustments on paid_adjustments.receivable_adjustment_id = a.id
    where a.company_id = company
      and a.kind = 'opening_balance'
      and a.recognized_at <= p_as_of
      and not filter_reps
      and (a.amount - coalesce(paid_adjustments.amount_paid, 0)) > 0.001

    order by 5, 3, 2;
end;
$$;

comment on function public.fetch_collections_report(timestamptz, uuid[]) is
  'As-of open invoices plus opening-balance adjustments. '
  'Opening rows are included only for All Sales Reps (no invented seller). '
  'Create-time customers.opening_balance without an adjustment row is omitted.';

revoke all on function public.fetch_collections_report(timestamptz, uuid[])
  from public;
grant execute on function public.fetch_collections_report(timestamptz, uuid[])
  to authenticated;
