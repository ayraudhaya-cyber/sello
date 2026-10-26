-- =============================================================================
-- 127 — Discount on a cheque collection
--
-- A cheque stays a cheque. The face value is payments.amount and cheques.amount.
-- Discount is stored beside it and, once the paper is in hand, reduces the
-- selected outstanding together with the face value. It is not a second cash
-- payment and it does not mark the cheque cleared.
--
-- Awaiting collection keeps the discount on the cheque and does not move
-- balances. Collecting later applies that stored discount once.
-- =============================================================================

alter table public.cheques
  add column if not exists discount_amount numeric(14, 2) not null default 0;

alter table public.cheques
  drop constraint if exists cheques_discount_amount_non_negative;

alter table public.cheques
  add constraint cheques_discount_amount_non_negative
  check (discount_amount >= 0);

comment on column public.cheques.discount_amount is
  'Write-off applied with this cheque. Outstanding drops by amount + discount once the cheque is collected. Not cash.';

-- ---------------------------------------------------------------------------
-- Payment created when the cheque is in hand
-- ---------------------------------------------------------------------------

create or replace function public._create_cheque_collection_payment(
  p_cheque_id uuid,
  p_allocations jsonb,
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
  ch public.cheques%rowtype;
  customer_row public.customers%rowtype;
  v_payment_id uuid;
  payment_status text := 'completed';
  approval_required boolean := false;
  bal_before numeric(14, 2);
  wallet_before numeric(14, 2);
  v_discount numeric(14, 2);
  settlement numeric(14, 2);
  alloc jsonb;
  alloc_total numeric(14, 2) := 0;
begin
  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  -- Already linked. Collecting again must not create a second payment.
  if ch.payment_id is not null then
    return ch.payment_id;
  end if;

  v_discount := round(coalesce(ch.discount_amount, 0), 2);
  if v_discount < 0 then
    raise exception 'Discount cannot be negative.';
  end if;

  if v_discount > 0.001 and not public.can_discount_collections() then
    raise exception 'You cannot add a discount on collections.';
  end if;

  settlement := round(ch.amount, 2) + v_discount;

  for alloc in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    alloc_total := alloc_total + coalesce((alloc->>'amount')::numeric, 0);
  end loop;

  if v_discount > 0.001 and alloc_total + 0.001 < settlement then
    raise exception
      'Allocate the full payment and discount to the order or opening balance.';
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
  where id = ch.customer_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Customer not found.';
  end if;

  bal_before := customer_row.current_balance;
  wallet_before := customer_row.wallet_balance;

  insert into public.payments (
    company_id,
    branch_id,
    customer_id,
    employee_id,
    payment_number,
    amount,
    discount_amount,
    method,
    status,
    reference,
    notes,
    visit_id,
    received_at,
    created_by,
    updated_by
  )
  values (
    company,
    ch.branch_id,
    ch.customer_id,
    emp,
    public.next_payment_number(company),
    ch.amount,
    v_discount,
    'cheque',
    payment_status,
    'Cheque ' || ch.cheque_number,
    coalesce(nullif(trim(coalesce(p_notes, '')), ''), ch.notes),
    ch.visit_id,
    timezone('utc', now()),
    emp,
    emp
  )
  returning id into v_payment_id;

  -- Cap is the face value plus the discount, so the write-off can be
  -- allocated without counting the cheque amount twice.
  perform public._insert_cheque_allocations(
    v_payment_id,
    company,
    ch.customer_id,
    settlement,
    p_allocations,
    emp
  );

  update public.cheques
  set
    payment_id = v_payment_id,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_cheque_id;

  if payment_status = 'completed' then
    perform public.apply_payment_financials(v_payment_id);
    perform public._sync_cheque_balance_after_payment(
      p_cheque_id,
      bal_before,
      wallet_before
    );
  end if;

  return v_payment_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_cheque — optional discount, same status rules
-- ---------------------------------------------------------------------------

drop function if exists public.create_cheque(
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean
);

create or replace function public.create_cheque(
  p_customer_id uuid,
  p_amount numeric,
  p_bank_name text,
  p_cheque_number text,
  p_holder_name text,
  p_cheque_date date,
  p_collection_date date default null,
  p_photo_path text default null,
  p_notes text default null,
  p_allocations jsonb default '[]'::jsonb,
  p_visit_id uuid default null,
  p_mark_collected boolean default false,
  p_discount_amount numeric default 0
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
  cheque_id uuid;
  label text;
  mark_collected boolean := coalesce(p_mark_collected, false)
    or p_collection_date is not null;
  initial_status text := 'awaiting_collection';
  v_discount numeric(14, 2) := round(coalesce(p_discount_amount, 0), 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Cheque amount must be greater than zero.';
  end if;

  if v_discount < 0 then
    raise exception 'Discount cannot be negative.';
  end if;

  if v_discount > 0.001 and not public.can_discount_collections() then
    raise exception 'You cannot add a discount on collections.';
  end if;

  if nullif(trim(coalesce(p_bank_name, '')), '') is null then
    raise exception 'Bank name is required.';
  end if;

  if nullif(trim(coalesce(p_cheque_number, '')), '') is null then
    raise exception 'Cheque number is required.';
  end if;

  if nullif(trim(coalesce(p_holder_name, '')), '') is null then
    raise exception 'Cheque holder name is required.';
  end if;

  if p_cheque_date is null then
    raise exception 'Cheque date is required.';
  end if;

  if mark_collected and p_collection_date is null then
    raise exception 'Collection date is required when marking a cheque collected.';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id
      and c.company_id = company
      and c.deleted_at is null
  ) then
    raise exception 'Customer not found.';
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

  select e.branch_id into branch
  from public.employees e
  where e.id = emp and e.company_id = company and e.deleted_at is null;

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
    raise exception 'No branch available for this cheque.';
  end if;

  label := public.next_cheque_number(company);

  if mark_collected then
    initial_status := 'collected';
  end if;

  insert into public.cheques (
    company_id,
    branch_id,
    customer_id,
    employee_id,
    cheque_number_label,
    amount,
    discount_amount,
    bank_name,
    cheque_number,
    holder_name,
    cheque_date,
    collection_date,
    photo_path,
    notes,
    status,
    visit_id,
    collected_at,
    collected_by,
    created_by,
    updated_by
  )
  values (
    company,
    branch,
    p_customer_id,
    emp,
    label,
    p_amount,
    v_discount,
    trim(p_bank_name),
    trim(p_cheque_number),
    trim(p_holder_name),
    p_cheque_date,
    case when mark_collected then p_collection_date else null end,
    nullif(trim(coalesce(p_photo_path, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    initial_status,
    p_visit_id,
    case when mark_collected then timezone('utc', now()) else null end,
    case when mark_collected then emp else null end,
    emp,
    emp
  )
  returning id into cheque_id;

  perform public._log_cheque_status(
    cheque_id, company, null, initial_status, emp, 'created'
  );

  if mark_collected then
    perform public._create_cheque_collection_payment(
      cheque_id,
      p_allocations,
      p_notes
    );
  end if;

  return cheque_id;
end;
$$;

revoke all on function public.create_cheque(
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean, numeric
) from public;
grant execute on function public.create_cheque(
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean, numeric
) to authenticated;

comment on function public.create_cheque(
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean, numeric
) is
  'Records a cheque. Discount is stored on the cheque and applied only when the paper is collected. Status stays on the cheque ledger.';
