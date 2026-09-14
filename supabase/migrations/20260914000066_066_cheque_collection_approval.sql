-- =============================================================================
-- Migration 066 — Cheque collection respects collection_approval_required
--
-- Builds on 065. Does NOT drop/recreate cheques. Existing applied cheques
-- (balance_applied_at set) are left unchanged.
--
-- When approval is required and the actor cannot auto-apply:
--   collect creates payments.status = pending (method=cheque); AR unchanged.
-- Owner/Manager approve_collection / approve_cheque_collection applies once.
-- =============================================================================

-- Effect amounts mirroring apply_payment_financials (non-wallet / wallet).
-- p_balance_before is the customer.current_balance BEFORE apply.
-- wallet_delta > 0 means wallet credit (non-wallet overpay).
-- For wallet method, wallet_delta is the wallet debit amount (payment.amount)
-- and ar_reduction is alloc_total.
create or replace function public._payment_apply_effect_amounts(
  p_payment_id uuid,
  p_balance_before numeric
)
returns table (
  ar_reduction numeric,
  wallet_delta numeric,
  alloc_total numeric
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  payment_row public.payments%rowtype;
  v_alloc numeric(14, 2) := 0;
  v_overpay numeric(14, 2) := 0;
  v_ar numeric(14, 2) := 0;
  v_wallet numeric(14, 2) := 0;
  v_balance numeric(14, 2) := coalesce(p_balance_before, 0);
begin
  select * into payment_row
  from public.payments
  where id = p_payment_id
    and deleted_at is null;

  if not found then
    return;
  end if;

  select coalesce(sum(pa.amount), 0)
    into v_alloc
  from public.payment_allocations pa
  where pa.payment_id = p_payment_id;

  if payment_row.method = 'wallet' then
    v_ar := v_alloc;
    v_wallet := payment_row.amount;
  else
    -- Same formulas as apply_payment_financials:
    --   ar_reduction := least(amount, current_balance)
    --   overpay := greatest(amount - alloc_total, 0)
    v_ar := least(payment_row.amount, v_balance);
    v_overpay := greatest(payment_row.amount - v_alloc, 0);
    v_wallet := v_overpay;
  end if;

  ar_reduction := v_ar;
  wallet_delta := v_wallet;
  alloc_total := v_alloc;
  return next;
end;
$$;

-- Snapshot AR/wallet effect onto the linked cheque after a completed payment.
-- Requires the authoritative pre-apply customer balance (p_bal_before).
-- payments / payment_allocations do NOT store historical AR vs wallet deltas;
-- missing balance_applied_at is an integrity exception (bounce refuses).
create or replace function public._sync_cheque_balance_after_payment(
  p_cheque_id uuid,
  p_bal_before numeric,
  p_wallet_before numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
  effect record;
begin
  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    return;
  end if;

  if ch.balance_applied_at is not null then
    return;
  end if;

  if ch.payment_id is null then
    return;
  end if;

  -- Prefer authoritative apply_payment_financials formulas with known balance_before
  -- (not a raw payment.amount assumption).
  select *
    into effect
  from public._payment_apply_effect_amounts(ch.payment_id, p_bal_before);

  update public.cheques
  set
    applied_ar_amount = coalesce(effect.ar_reduction, 0),
    applied_wallet_amount = coalesce(effect.wallet_delta, 0),
    balance_applied_at = timezone('utc', now()),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_cheque_id;
end;
$$;

-- Create cheque payment (pending or completed) and optionally apply financials.
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
  payment_id uuid;
  payment_status text := 'completed';
  approval_required boolean := false;
  bal_before numeric(14, 2);
  wallet_before numeric(14, 2);
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

  -- Already linked
  if ch.payment_id is not null then
    return ch.payment_id;
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
    'cheque',
    payment_status,
    'Cheque ' || ch.cheque_number,
    coalesce(nullif(trim(coalesce(p_notes, '')), ''), ch.notes),
    ch.visit_id,
    timezone('utc', now()),
    emp,
    emp
  )
  returning id into payment_id;

  perform public._insert_cheque_allocations(
    payment_id,
    company,
    ch.customer_id,
    ch.amount,
    p_allocations,
    emp
  );

  update public.cheques
  set
    payment_id = payment_id,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_cheque_id;

  if payment_status = 'completed' then
    perform public.apply_payment_financials(payment_id);
    perform public._sync_cheque_balance_after_payment(
      p_cheque_id,
      bal_before,
      wallet_before
    );
  end if;

  return payment_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_cheque — mark collected respects approval
-- ---------------------------------------------------------------------------

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
  p_mark_collected boolean default false
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
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Cheque amount must be greater than zero.';
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
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean
) from public;
grant execute on function public.create_cheque(
  uuid, numeric, text, text, text, date, date, text, text, jsonb, uuid, boolean
) to authenticated;

-- ---------------------------------------------------------------------------
-- collect_cheque
-- ---------------------------------------------------------------------------

create or replace function public.collect_cheque(
  p_cheque_id uuid,
  p_collection_date date,
  p_allocations jsonb default '[]'::jsonb,
  p_photo_path text default null,
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
  from_status text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if p_collection_date is null then
    raise exception 'Collection date is required.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  -- Idempotent: already collected (with or without applied balance)
  if ch.status = 'collected' and ch.payment_id is not null then
    return ch.id;
  end if;

  if ch.balance_applied_at is not null then
    return ch.id;
  end if;

  if ch.status <> 'awaiting_collection' then
    raise exception 'Only awaiting-collection cheques can be collected.';
  end if;

  from_status := ch.status;

  update public.cheques
  set
    status = 'collected',
    collection_date = p_collection_date,
    photo_path = coalesce(nullif(trim(coalesce(p_photo_path, '')), ''), photo_path),
    notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), notes),
    collected_at = timezone('utc', now()),
    collected_by = emp,
    updated_by = emp
  where id = p_cheque_id;

  perform public._create_cheque_collection_payment(
    p_cheque_id,
    p_allocations,
    p_notes
  );

  perform public._log_cheque_status(
    p_cheque_id, company, from_status, 'collected', emp, null
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.collect_cheque(uuid, date, jsonb, text, text) from public;
grant execute on function public.collect_cheque(uuid, date, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- deposit only after financial apply
-- ---------------------------------------------------------------------------

create or replace function public.deposit_cheque(p_cheque_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can deposit cheques.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'deposited' then
    return ch.id;
  end if;

  if ch.status <> 'collected' then
    raise exception 'Only collected cheques can be deposited.';
  end if;

  if ch.balance_applied_at is null then
    raise exception
      'Approve this cheque collection before depositing.';
  end if;

  update public.cheques
  set
    status = 'deposited',
    deposited_at = timezone('utc', now()),
    deposited_by = emp,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id, company, 'collected', 'deposited', emp, null
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.deposit_cheque(uuid) from public;
grant execute on function public.deposit_cheque(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- approve_collection — sync linked cheque after apply (idempotent)
-- ---------------------------------------------------------------------------

create or replace function public.approve_collection(p_payment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  payment_row public.payments%rowtype;
  cheque_id uuid;
  bal_before numeric(14, 2);
  wallet_before numeric(14, 2);
  customer_id uuid;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_review_collections() then
    raise exception 'Not permitted to approve collections.';
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

  -- Idempotent: already completed. Do not invent a cheque financial snapshot —
  -- payments do not store historical AR/wallet deltas. Missing balance_applied_at
  -- remains an integrity exception (bounce will refuse).
  if payment_row.status = 'completed' then
    return p_payment_id;
  end if;

  if payment_row.status <> 'pending' then
    raise exception 'Only pending collections can be approved.';
  end if;

  customer_id := payment_row.customer_id;

  select current_balance, wallet_balance
    into bal_before, wallet_before
  from public.customers
  where id = customer_id
    and company_id = company
    and deleted_at is null
  for update;

  update public.payments
  set
    status = 'completed',
    reviewed_by = emp,
    reviewed_at = timezone('utc', now()),
    rejection_reason = null,
    updated_by = emp
  where id = p_payment_id;

  perform public.apply_payment_financials(p_payment_id);

  select c.id into cheque_id
  from public.cheques c
  where c.payment_id = p_payment_id
    and c.company_id = company
    and c.deleted_at is null
  limit 1;

  if cheque_id is not null then
    perform public._sync_cheque_balance_after_payment(
      cheque_id,
      bal_before,
      wallet_before
    );
    perform public._log_cheque_status(
      cheque_id,
      company,
      'collected',
      'collected',
      emp,
      'collection approved'
    );
  end if;

  return p_payment_id;
end;
$$;

revoke all on function public.approve_collection(uuid) from public;
grant execute on function public.approve_collection(uuid) to authenticated;

-- Convenience: approve by cheque id (same financial gate)
create or replace function public.approve_cheque_collection(p_cheque_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  ch public.cheques%rowtype;
  payment_row public.payments%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_review_collections() then
    raise exception 'Not permitted to approve collections.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.balance_applied_at is not null then
    return ch.id;
  end if;

  if ch.status <> 'collected' then
    raise exception 'Only collected cheques can be approved.';
  end if;

  if ch.payment_id is null then
    raise exception 'Cheque has no linked collection to approve.';
  end if;

  select * into payment_row
  from public.payments
  where id = ch.payment_id
    and company_id = company
    and deleted_at is null;

  if not found then
    raise exception 'Linked payment not found.';
  end if;

  if payment_row.status = 'completed' then
    -- Sync snapshot if missing
    perform public.approve_collection(ch.payment_id);
    return ch.id;
  end if;

  if payment_row.status <> 'pending' then
    raise exception 'Linked collection is not pending approval.';
  end if;

  perform public.approve_collection(ch.payment_id);
  return ch.id;
end;
$$;

revoke all on function public.approve_cheque_collection(uuid) from public;
grant execute on function public.approve_cheque_collection(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- reject_collection — return cheque to awaiting when pending cheque payment
-- ---------------------------------------------------------------------------

create or replace function public.reject_collection(
  p_payment_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  payment_row public.payments%rowtype;
  reason text := nullif(trim(coalesce(p_reason, '')), '');
  cheque_id uuid;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_review_collections() then
    raise exception 'Not permitted to reject collections.';
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

  if payment_row.status <> 'pending' then
    raise exception 'Only pending collections can be rejected.';
  end if;

  update public.payments
  set
    status = 'rejected',
    reviewed_by = emp,
    reviewed_at = timezone('utc', now()),
    rejection_reason = reason,
    cancelled_at = timezone('utc', now()),
    updated_by = emp
  where id = p_payment_id;

  -- Unlink cheque so a new collection can be recorded; keep rejected payment.
  select c.id into cheque_id
  from public.cheques c
  where c.payment_id = p_payment_id
    and c.company_id = company
    and c.deleted_at is null
  for update;

  if cheque_id is not null then
    update public.cheques
    set
      payment_id = null,
      status = 'awaiting_collection',
      collection_date = null,
      collected_at = null,
      collected_by = null,
      balance_applied_at = null,
      applied_ar_amount = 0,
      applied_wallet_amount = 0,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = cheque_id;

    perform public._log_cheque_status(
      cheque_id,
      company,
      'collected',
      'awaiting_collection',
      emp,
      coalesce(reason, 'collection rejected')
    );
  end if;

  return p_payment_id;
end;
$$;

revoke all on function public.reject_collection(uuid, text) from public;
grant execute on function public.reject_collection(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- bounce: only after balance applied (pending-approval use reject/cancel)
-- ---------------------------------------------------------------------------

create or replace function public.bounce_cheque(
  p_cheque_id uuid,
  p_reason text default null
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
  payment_status text;
  from_status text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can bounce cheques.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'bounced' then
    perform public._reverse_cheque_collection_ledger(p_cheque_id);
    return ch.id;
  end if;

  if ch.status not in ('collected', 'deposited', 'cleared') then
    raise exception 'Only collected, deposited, or cleared cheques can bounce.';
  end if;

  if ch.balance_applied_at is null then
    if ch.payment_id is not null then
      select p.status into payment_status
      from public.payments p
      where p.id = ch.payment_id
        and p.company_id = company
        and p.deleted_at is null;
    end if;

    if payment_status = 'pending' then
      raise exception
        'This cheque collection is still pending approval. Reject or cancel instead of bouncing.';
    end if;

    raise exception
      'Cannot bounce this cheque: financial snapshot is missing. '
      'Refusing unsafe reversal.';
  end if;

  from_status := ch.status;

  perform public._reverse_cheque_collection_ledger(p_cheque_id);

  update public.cheques
  set
    status = 'bounced',
    bounced_at = timezone('utc', now()),
    bounced_by = emp,
    bounce_reason = nullif(trim(coalesce(p_reason, '')), ''),
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id, company, from_status, 'bounced', emp, p_reason
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.bounce_cheque(uuid, text) from public;
grant execute on function public.bounce_cheque(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Dashboard stats — pending approval vs applied collected
-- ---------------------------------------------------------------------------

create or replace function public.cheque_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  company uuid := public.current_company_id();
  today date := (timezone('utc', now()))::date;
begin
  if company is null then
    raise exception 'Session context missing.';
  end if;

  return (
    select jsonb_build_object(
      'awaiting_collection', count(*) filter (where status = 'awaiting_collection'),
      'due_today', count(*) filter (
        where status = 'awaiting_collection'
          and (
            collection_date = today
            or (collection_date is null and cheque_date <= today)
          )
      ),
      'pending_approval', count(*) filter (
        where status = 'collected'
          and balance_applied_at is null
      ),
      'collected', count(*) filter (
        where status = 'collected'
          and balance_applied_at is not null
      ),
      'deposited', count(*) filter (where status = 'deposited'),
      'cleared', count(*) filter (where status = 'cleared'),
      'bounced', count(*) filter (where status = 'bounced'),
      'cancelled', count(*) filter (where status = 'cancelled'),
      'collected_pending_clearance_amount', coalesce(sum(amount) filter (
        where status in ('collected', 'deposited')
          and balance_applied_at is not null
      ), 0)
    )
    from public.cheques
    where company_id = company
      and deleted_at is null
  );
end;
$$;

revoke all on function public.cheque_dashboard_stats() from public;
grant execute on function public.cheque_dashboard_stats() to authenticated;

comment on function public.approve_cheque_collection(uuid) is
  'Owner/Manager: approve pending cheque collection; applies AR once via linked payment.';

comment on function public._create_cheque_collection_payment(uuid, jsonb, text) is
  'Creates pending or completed cheque payment based on collection_approval_required.';
