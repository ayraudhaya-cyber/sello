-- =============================================================================
-- 093 — Safe operational corrections + inventory selling-price valuation
--
-- Principle: correct honest mistakes without silently rewriting financial
-- history. Sensitive amendments are Owner/Manager RPCs only.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Role gate — same Hub financial set as opening-balance adjustments
-- ---------------------------------------------------------------------------

create or replace function public.can_correct_financials()
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

comment on function public.can_correct_financials() is
  'Owner / Administrator / Manager may reverse-and-replace payments, '
  'reassign order ownership, edit cheque details, and correct opening AR.';

revoke all on function public.can_correct_financials() from public;
grant execute on function public.can_correct_financials() to authenticated;

-- ---------------------------------------------------------------------------
-- Inventory stock at selling price (not cost-gated)
-- ---------------------------------------------------------------------------

create or replace function public.inventory_stock_selling_value(
  p_branch_id uuid default null
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select sum(i.quantity * coalesce(v.selling_price, 0))
      from public.inventory i
      join public.products p on p.id = i.product_id
      join public.product_variants v on v.id = i.variant_id
      where i.company_id = public.current_company_id()
        and p.deleted_at is null
        and p.is_active
        and (p_branch_id is null or i.branch_id = p_branch_id)
    ),
    0
  );
$$;

comment on function public.inventory_stock_selling_value(uuid) is
  'On-hand quantity × variant selling_price. Visible to Hub roles; not cost-gated.';

revoke all on function public.inventory_stock_selling_value(uuid) from public;
grant execute on function public.inventory_stock_selling_value(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Payments: store applied ledger effects so reverse is reconstructable
-- ---------------------------------------------------------------------------

alter table public.payments
  add column if not exists applied_ar_amount numeric(14, 2) not null default 0;

alter table public.payments
  add column if not exists applied_wallet_amount numeric(14, 2) not null default 0;

alter table public.payments
  add column if not exists applied_wallet_debit numeric(14, 2) not null default 0;

alter table public.payments
  add column if not exists corrects_payment_id uuid
    references public.payments (id) on delete restrict;

alter table public.payments
  add column if not exists corrected_by_payment_id uuid
    references public.payments (id) on delete restrict;

alter table public.payments
  add column if not exists correction_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_applied_ar_non_negative'
  ) then
    alter table public.payments
      add constraint payments_applied_ar_non_negative
        check (applied_ar_amount >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_applied_wallet_non_negative'
  ) then
    alter table public.payments
      add constraint payments_applied_wallet_non_negative
        check (applied_wallet_amount >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_applied_wallet_debit_non_negative'
  ) then
    alter table public.payments
      add constraint payments_applied_wallet_debit_non_negative
        check (applied_wallet_debit >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_correction_reason_not_blank'
  ) then
    alter table public.payments
      add constraint payments_correction_reason_not_blank
        check (correction_reason is null or length(trim(correction_reason)) > 0);
  end if;
end $$;

comment on column public.payments.applied_ar_amount is
  'AR reduced when this completed payment was applied. Used to reverse safely.';
comment on column public.payments.applied_wallet_amount is
  'Wallet credit (overpayment) issued when this payment was applied.';
comment on column public.payments.applied_wallet_debit is
  'Wallet debit when method=wallet. Restored on reverse.';
comment on column public.payments.corrects_payment_id is
  'The cancelled original this completed payment replaces.';
comment on column public.payments.corrected_by_payment_id is
  'Replacement payment created by correct_completed_payment.';

-- ---------------------------------------------------------------------------
-- Opening-balance reverse marker (append-only; never overwrite amount)
-- ---------------------------------------------------------------------------

alter table public.customer_receivable_adjustments
  add column if not exists reversed_at timestamptz;

alter table public.customer_receivable_adjustments
  add column if not exists reversed_by uuid
    references public.employees (id) on delete set null;

alter table public.customer_receivable_adjustments
  add column if not exists corrects_adjustment_id uuid
    references public.customer_receivable_adjustments (id) on delete restrict;

comment on column public.customer_receivable_adjustments.reversed_at is
  'Set when an Owner/Manager replaces this opening AR with a corrected document.';

-- ---------------------------------------------------------------------------
-- apply_payment_financials — snapshot applied AR / wallet
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
  bal_before numeric(14, 2);
  wallet_before numeric(14, 2);
  bal_after numeric(14, 2);
  wallet_after numeric(14, 2);
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
  bal_before := customer_row.current_balance;
  wallet_before := customer_row.wallet_balance;

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

  select current_balance, wallet_balance
    into bal_after, wallet_after
  from public.customers
  where id = payment_row.customer_id;

  update public.payments
  set
    applied_ar_amount = greatest(bal_before - coalesce(bal_after, bal_before), 0),
    applied_wallet_amount = greatest(coalesce(wallet_after, wallet_before) - wallet_before, 0),
    applied_wallet_debit = greatest(wallet_before - coalesce(wallet_after, wallet_before), 0),
    updated_by = emp
  where id = p_payment_id;

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
-- Reverse a completed payment's ledger. Does not delete the row.
-- ---------------------------------------------------------------------------

create or replace function public._reverse_completed_payment_ledger(
  p_payment_id uuid
)
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
  alloc_total numeric(14, 2) := 0;
  ar_restore numeric(14, 2);
  wallet_credit numeric(14, 2);
  wallet_debit numeric(14, 2);
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

  if payment_row.status <> 'completed' then
    return;
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

  select coalesce(sum(amount), 0) into alloc_total
  from public.payment_allocations
  where payment_id = p_payment_id;

  ar_restore := coalesce(payment_row.applied_ar_amount, 0);
  wallet_credit := coalesce(payment_row.applied_wallet_amount, 0);
  wallet_debit := coalesce(payment_row.applied_wallet_debit, 0);

  -- Historical rows recorded before applied_* existed.
  if ar_restore = 0 and wallet_credit = 0 and wallet_debit = 0 then
    if payment_row.method = 'wallet' then
      wallet_debit := payment_row.amount;
      ar_restore := alloc_total;
    else
      ar_restore := alloc_total;
      wallet_credit := greatest(payment_row.amount - alloc_total, 0);
    end if;
  end if;

  if wallet_credit > customer_row.wallet_balance + 0.001 then
    raise exception
      'Cannot reverse this payment because the customer wallet no longer '
      'holds the overpayment that was issued. Record a wallet adjustment first.';
  end if;

  update public.customers
  set
    current_balance = current_balance + ar_restore,
    wallet_balance = wallet_balance - wallet_credit + wallet_debit,
    updated_by = emp
  where id = payment_row.customer_id;

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

revoke all on function public._reverse_completed_payment_ledger(uuid) from public;

-- ---------------------------------------------------------------------------
-- Correct a payment: reverse original (if applied) + receive replacement
-- ---------------------------------------------------------------------------

create or replace function public.correct_completed_payment(
  p_payment_id uuid,
  p_amount numeric,
  p_method text,
  p_allocations jsonb default '[]'::jsonb,
  p_reference text default null,
  p_notes text default null,
  p_reason text default null,
  p_customer_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  original public.payments%rowtype;
  new_id uuid;
  reason_text text;
  customer_id uuid;
  from_label text;
  to_label text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_correct_financials() then
    raise exception 'Only Owner or Manager can correct a payment.';
  end if;

  reason_text := nullif(trim(coalesce(p_reason, '')), '');
  if reason_text is null then
    raise exception 'Enter a short reason for this payment correction.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  if p_method not in ('cash', 'card', 'bank_transfer', 'wallet', 'credit_settlement') then
    raise exception 'Unsupported payment method.';
  end if;

  select * into original
  from public.payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if original.corrected_by_payment_id is not null then
    raise exception 'This payment has already been corrected.';
  end if;

  if original.status not in ('completed', 'pending') then
    raise exception 'Only completed or pending-review payments can be corrected.';
  end if;

  customer_id := coalesce(p_customer_id, original.customer_id);

  if not exists (
    select 1 from public.customers c
    where c.id = customer_id
      and c.company_id = company
      and c.deleted_at is null
  ) then
    raise exception 'Customer not found.';
  end if;

  if original.status = 'completed' then
    perform public._reverse_completed_payment_ledger(p_payment_id);
  end if;

  update public.payments
  set
    status = 'cancelled',
    cancelled_at = timezone('utc', now()),
    correction_reason = reason_text,
    notes = case
      when original.notes is null then 'Corrected: ' || reason_text
      else original.notes || E'\nCorrected: ' || reason_text
    end,
    updated_by = emp
  where id = p_payment_id;

  if original.status = 'completed' then
    perform public._reverse_completed_payment_ledger(p_payment_id);
    -- refresh_order_payment_status already ran; cancelled row is excluded
    -- because status is no longer completed. Call again after the status flip.
    perform public._refresh_payment_order_statuses(p_payment_id);
  end if;

  -- Status was flipped after the first reverse so refresh again now that
  -- allocations no longer count as completed.
  perform public._refresh_payment_order_statuses(p_payment_id);

  new_id := public.receive_payment(
    customer_id,
    p_amount,
    p_method,
    coalesce(p_allocations, '[]'::jsonb),
    p_reference,
    coalesce(p_notes, 'Correction of ' || original.payment_number),
    original.visit_id
  );

  update public.payments
  set
    corrects_payment_id = p_payment_id,
    correction_reason = reason_text,
    updated_by = emp
  where id = new_id
    and company_id = company;

  update public.payments
  set
    corrected_by_payment_id = new_id,
    updated_by = emp
  where id = p_payment_id;

  select payment_number into from_label from public.payments where id = p_payment_id;
  select payment_number into to_label from public.payments where id = new_id;

  perform public.log_company_activity(
    company,
    'payments',
    'payment_corrected',
    'Payment corrected from ' || coalesce(from_label, 'original')
      || ' to ' || coalesce(to_label, 'new payment'),
    emp,
    null,
    'payment',
    new_id,
    jsonb_build_object(
      'original_payment_id', p_payment_id,
      'corrected_payment_id', new_id,
      'from_amount', original.amount,
      'to_amount', p_amount,
      'from_method', original.method,
      'to_method', p_method,
      'from_customer_id', original.customer_id,
      'to_customer_id', customer_id,
      'reason', reason_text
    )
  );

  return new_id;
end;
$$;

-- Helper used above — defined before correct_completed_payment is first
-- invoked at runtime; create it now if the previous body referenced it.

create or replace function public._refresh_payment_order_statuses(
  p_payment_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  alloc_row public.payment_allocations%rowtype;
begin
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

revoke all on function public._refresh_payment_order_statuses(uuid) from public;

-- Recreate correct_completed_payment now that the helper exists. The first
-- definition already referenced it; PostgreSQL resolves at call time so this
-- replace keeps a single clean body without the duplicate reverse.

create or replace function public.correct_completed_payment(
  p_payment_id uuid,
  p_amount numeric,
  p_method text,
  p_allocations jsonb default '[]'::jsonb,
  p_reference text default null,
  p_notes text default null,
  p_reason text default null,
  p_customer_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  original public.payments%rowtype;
  new_id uuid;
  reason_text text;
  customer_id uuid;
  from_label text;
  to_label text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_correct_financials() then
    raise exception 'Only Owner or Manager can correct a payment.';
  end if;

  reason_text := nullif(trim(coalesce(p_reason, '')), '');
  if reason_text is null then
    raise exception 'Enter a short reason for this payment correction.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  if p_method not in ('cash', 'card', 'bank_transfer', 'wallet', 'credit_settlement') then
    raise exception 'Unsupported payment method.';
  end if;

  select * into original
  from public.payments
  where id = p_payment_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if original.corrected_by_payment_id is not null then
    raise exception 'This payment has already been corrected.';
  end if;

  if original.status not in ('completed', 'pending') then
    raise exception 'Only completed or pending-review payments can be corrected.';
  end if;

  customer_id := coalesce(p_customer_id, original.customer_id);

  if not exists (
    select 1 from public.customers c
    where c.id = customer_id
      and c.company_id = company
      and c.deleted_at is null
  ) then
    raise exception 'Customer not found.';
  end if;

  if original.status = 'completed' then
    perform public._reverse_completed_payment_ledger(p_payment_id);
  end if;

  update public.payments
  set
    status = 'cancelled',
    cancelled_at = timezone('utc', now()),
    correction_reason = reason_text,
    notes = case
      when original.notes is null then 'Corrected: ' || reason_text
      else original.notes || E'\nCorrected: ' || reason_text
    end,
    updated_by = emp
  where id = p_payment_id;

  perform public._refresh_payment_order_statuses(p_payment_id);

  new_id := public.receive_payment(
    customer_id,
    p_amount,
    p_method,
    coalesce(p_allocations, '[]'::jsonb),
    p_reference,
    coalesce(nullif(trim(coalesce(p_notes, '')), ''), 'Correction of ' || original.payment_number),
    original.visit_id
  );

  update public.payments
  set
    corrects_payment_id = p_payment_id,
    correction_reason = reason_text,
    updated_by = emp
  where id = new_id
    and company_id = company;

  update public.payments
  set
    corrected_by_payment_id = new_id,
    updated_by = emp
  where id = p_payment_id;

  select payment_number into from_label from public.payments where id = p_payment_id;
  select payment_number into to_label from public.payments where id = new_id;

  perform public.log_company_activity(
    company,
    'payments',
    'payment_corrected',
    'Payment corrected from ' || coalesce(from_label, 'original')
      || ' to ' || coalesce(to_label, 'new payment'),
    emp,
    null,
    'payment',
    new_id,
    jsonb_build_object(
      'original_payment_id', p_payment_id,
      'corrected_payment_id', new_id,
      'from_amount', original.amount,
      'to_amount', p_amount,
      'from_method', original.method,
      'to_method', p_method,
      'from_customer_id', original.customer_id,
      'to_customer_id', customer_id,
      'reason', reason_text
    )
  );

  return new_id;
end;
$$;

comment on function public.correct_completed_payment(
  uuid, numeric, text, jsonb, text, text, text, uuid
) is
  'Owner/Manager reverse-and-replace for a completed or pending payment. '
  'Does not UPDATE applied financial fields on the original row.';

revoke all on function public.correct_completed_payment(
  uuid, numeric, text, jsonb, text, text, text, uuid
) from public;
grant execute on function public.correct_completed_payment(
  uuid, numeric, text, jsonb, text, text, text, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- Reassign Sales Rep on an order (ownership / reporting only)
-- ---------------------------------------------------------------------------

create or replace function public.reassign_order_sales_rep(
  p_order_id uuid,
  p_employee_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  order_row public.orders%rowtype;
  from_emp public.employees%rowtype;
  to_emp public.employees%rowtype;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_correct_financials() then
    raise exception 'Only Owner or Manager can change the Sales Rep on an order.';
  end if;

  select * into order_row
  from public.orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if order_row.status = 'cancelled' then
    raise exception 'Cancelled orders cannot be reassigned.';
  end if;

  if order_row.employee_id = p_employee_id then
    return;
  end if;

  select * into to_emp
  from public.employees
  where id = p_employee_id
    and company_id = company
    and deleted_at is null
    and is_active = true;

  if not found then
    raise exception 'Sales Rep not found in this company.';
  end if;

  select * into from_emp
  from public.employees
  where id = order_row.employee_id
    and company_id = company;

  update public.orders
  set
    employee_id = p_employee_id,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_order_id
    and company_id = company;

  perform public.log_company_activity(
    company,
    'orders',
    'sales_rep_changed',
    'Sales Rep changed from '
      || coalesce(from_emp.full_name, 'unknown')
      || ' to '
      || to_emp.full_name,
    emp,
    null,
    'order',
    p_order_id,
    jsonb_build_object(
      'from_employee_id', order_row.employee_id,
      'to_employee_id', p_employee_id,
      'from_name', from_emp.full_name,
      'to_name', to_emp.full_name,
      'order_number', order_row.order_number
    )
  );
end;
$$;

comment on function public.reassign_order_sales_rep(uuid, uuid) is
  'Owner/Manager reporting ownership change. Does not rewrite payments or stock.';

revoke all on function public.reassign_order_sales_rep(uuid, uuid) from public;
grant execute on function public.reassign_order_sales_rep(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Safe customer change on a draft with no payments
-- ---------------------------------------------------------------------------

create or replace function public.reassign_order_customer(
  p_order_id uuid,
  p_customer_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  order_row public.orders%rowtype;
  from_name text;
  to_name text;
  payment_count int;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_correct_financials() then
    raise exception 'Only Owner or Manager can change the customer on an order.';
  end if;

  select * into order_row
  from public.orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if order_row.status <> 'draft' then
    raise exception
      'The customer can only be changed while this order is still a draft. '
      'After it is placed or delivered, changing customer would mix up outstanding balances. '
      'Cancel this order and create a new one for the correct customer.';
  end if;

  select count(*) into payment_count
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = p_order_id
    and p.deleted_at is null
    and p.status in ('completed', 'pending');

  if payment_count > 0 then
    raise exception
      'This draft already has a collection against it. '
      'Correct or cancel that payment first, then change the customer.';
  end if;

  if order_row.customer_id = p_customer_id then
    return;
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id
      and c.company_id = company
      and c.deleted_at is null
      and c.is_active = true
  ) then
    raise exception 'Customer not found.';
  end if;

  select name into from_name from public.customers where id = order_row.customer_id;
  select name into to_name from public.customers where id = p_customer_id;

  update public.orders
  set
    customer_id = p_customer_id,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = p_order_id
    and company_id = company;

  perform public.log_company_activity(
    company,
    'orders',
    'customer_changed',
    'Customer changed from '
      || coalesce(from_name, 'unknown')
      || ' to '
      || coalesce(to_name, 'unknown'),
    emp,
    null,
    'order',
    p_order_id,
    jsonb_build_object(
      'from_customer_id', order_row.customer_id,
      'to_customer_id', p_customer_id,
      'from_name', from_name,
      'to_name', to_name
    )
  );
end;
$$;

comment on function public.reassign_order_customer(uuid, uuid) is
  'Owner/Manager draft-only customer correction. Refuses after place/pay/fulfill.';

revoke all on function public.reassign_order_customer(uuid, uuid) from public;
grant execute on function public.reassign_order_customer(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Cheque descriptive details (not amount / customer / status)
-- ---------------------------------------------------------------------------

create or replace function public.update_cheque_details(
  p_cheque_id uuid,
  p_bank_name text default null,
  p_cheque_number text default null,
  p_holder_name text default null,
  p_cheque_date date default null,
  p_notes text default null,
  p_photo_path text default null
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
  role_code text := coalesce(public.current_role_code(), '');
  can_hub boolean := public.can_correct_financials();
  v_bank_name text;
  v_cheque_number text;
  v_holder_name text;
  before_json jsonb;
  after_json jsonb;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id
    and company_id = company
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status in ('cancelled', 'bounced') then
    raise exception 'Cancelled or returned cheques cannot be edited.';
  end if;

  if not can_hub then
    if role_code <> 'sales_representative' then
      raise exception 'You cannot edit this cheque.';
    end if;
    if ch.employee_id <> emp then
      raise exception 'You can only edit cheques you recorded.';
    end if;
    if ch.status <> 'awaiting_collection' then
      raise exception
        'After a cheque is collected, only Owner or Manager can update its details.';
    end if;
  end if;

  v_bank_name := coalesce(nullif(trim(p_bank_name), ''), ch.bank_name);
  v_cheque_number := coalesce(nullif(trim(p_cheque_number), ''), ch.cheque_number);
  v_holder_name := coalesce(nullif(trim(p_holder_name), ''), ch.holder_name);

  if length(v_bank_name) = 0 or length(v_cheque_number) = 0 or length(v_holder_name) = 0 then
    raise exception 'Bank, cheque number, and holder are required.';
  end if;

  before_json := jsonb_build_object(
    'bank_name', ch.bank_name,
    'cheque_number', ch.cheque_number,
    'holder_name', ch.holder_name,
    'cheque_date', ch.cheque_date,
    'notes', ch.notes,
    'photo_path', ch.photo_path
  );

  update public.cheques
  set
    bank_name = v_bank_name,
    cheque_number = v_cheque_number,
    holder_name = v_holder_name,
    cheque_date = coalesce(p_cheque_date, ch.cheque_date),
    notes = case
      when p_notes is null then ch.notes
      else nullif(trim(p_notes), '')
    end,
    photo_path = case
      when p_photo_path is null then ch.photo_path
      else nullif(trim(p_photo_path), '')
    end
  where id = p_cheque_id
    and company_id = company;

  select * into ch from public.cheques where id = p_cheque_id;

  after_json := jsonb_build_object(
    'bank_name', ch.bank_name,
    'cheque_number', ch.cheque_number,
    'holder_name', ch.holder_name,
    'cheque_date', ch.cheque_date,
    'notes', ch.notes,
    'photo_path', ch.photo_path
  );

  if before_json = after_json then
    return;
  end if;

  perform public.log_company_activity(
    company,
    'payments',
    'cheque_details_updated',
    'Cheque details updated for ' || coalesce(ch.cheque_number_label, 'cheque'),
    emp,
    null,
    'cheque',
    p_cheque_id,
    jsonb_build_object('before', before_json, 'after', after_json)
  );
end;
$$;

comment on function public.update_cheque_details(
  uuid, text, text, text, date, text, text
) is
  'Descriptive cheque fields only. Amount, customer, and status stay on lifecycle RPCs.';

revoke all on function public.update_cheque_details(
  uuid, text, text, text, date, text, text
) from public;
grant execute on function public.update_cheque_details(
  uuid, text, text, text, date, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- Opening-balance correction: reverse original (no allocations) + insert new
-- ---------------------------------------------------------------------------

create or replace function public.correct_opening_balance_adjustment(
  p_adjustment_id uuid,
  p_amount numeric,
  p_reason text,
  p_notes text default null,
  p_reference_number text default null,
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
  original public.customer_receivable_adjustments%rowtype;
  paid numeric(14, 2);
  new_id uuid;
  amount_value numeric(14, 2);
  reason_text text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_correct_financials() then
    raise exception 'Only Owner or Manager can correct an opening balance.';
  end if;

  reason_text := nullif(trim(coalesce(p_reason, '')), '');
  if reason_text is null then
    raise exception 'Enter a short reason for this opening-balance correction.';
  end if;

  amount_value := round(coalesce(p_amount, 0)::numeric, 2);
  if amount_value <= 0 then
    raise exception 'Corrected opening balance must be greater than zero.';
  end if;

  select * into original
  from public.customer_receivable_adjustments
  where id = p_adjustment_id
    and company_id = company
  for update;

  if not found then
    raise exception 'Opening balance not found.';
  end if;

  if original.kind <> 'opening_balance' then
    raise exception 'Only opening-balance documents can be corrected this way.';
  end if;

  if original.reversed_at is not null then
    raise exception 'This opening balance has already been corrected.';
  end if;

  select coalesce(sum(pa.amount), 0) into paid
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.receivable_adjustment_id = p_adjustment_id
    and p.deleted_at is null
    and p.status in ('completed', 'pending');

  if paid > 0.001 then
    raise exception
      'This opening balance already has collections against it. '
      'Correct those payments first, then correct the opening balance.';
  end if;

  if (
    select c.current_balance
    from public.customers c
    where c.id = original.customer_id
      and c.company_id = company
  ) + 0.001 < original.amount then
    raise exception
      'This customer''s outstanding is lower than the original opening balance, '
      'so part of it has already been collected. Correct those payments first.';
  end if;

  update public.customers
  set
    opening_balance = greatest(opening_balance - original.amount, 0),
    current_balance = greatest(current_balance - original.amount, 0),
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = original.customer_id
    and company_id = company;

  update public.customer_receivable_adjustments
  set
    reversed_at = timezone('utc', now()),
    reversed_by = emp,
    notes = case
      when original.notes is null then 'Corrected: ' || reason_text
      else original.notes || E'\nCorrected: ' || reason_text
    end
  where id = p_adjustment_id;

  new_id := public.record_opening_balance_adjustment(
    original.customer_id,
    amount_value,
    coalesce(nullif(trim(coalesce(p_notes, '')), ''), reason_text),
    coalesce(p_recognized_at, original.recognized_at),
    p_reference_number
  );

  update public.customer_receivable_adjustments
  set corrects_adjustment_id = p_adjustment_id
  where id = new_id
    and company_id = company;

  perform public.log_company_activity(
    company,
    'customers',
    'opening_balance_adjusted',
    'Opening balance corrected',
    emp,
    null,
    'customer',
    original.customer_id,
    jsonb_build_object(
      'original_adjustment_id', p_adjustment_id,
      'corrected_adjustment_id', new_id,
      'from_amount', original.amount,
      'to_amount', amount_value,
      'reason', reason_text
    )
  );

  return new_id;
end;
$$;

comment on function public.correct_opening_balance_adjustment(
  uuid, numeric, text, text, text, timestamptz
) is
  'Owner/Manager reverse-and-replace for an unallocated opening-balance document.';

revoke all on function public.correct_opening_balance_adjustment(
  uuid, numeric, text, text, text, timestamptz
) from public;
grant execute on function public.correct_opening_balance_adjustment(
  uuid, numeric, text, text, text, timestamptz
) to authenticated;

-- Remaining / collections report skip reversed opening AR
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

  if adj_row.reversed_at is not null then
    return 0;
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
  document_type text,
  reference_number text
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
      'Invoice'::text,
      null::text
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
      'Opening balance'::text,
      a.reference_number
    from public.customer_receivable_adjustments a
    inner join public.customers c on c.id = a.customer_id
    left join paid_adjustments on paid_adjustments.receivable_adjustment_id = a.id
    where a.company_id = company
      and a.kind = 'opening_balance'
      and a.reversed_at is null
      and a.recognized_at <= p_as_of
      and not filter_reps
      and (a.amount - coalesce(paid_adjustments.amount_paid, 0)) > 0.001

    order by 5, 3, 2;
end;
$$;

revoke all on function public.fetch_collections_report(timestamptz, uuid[])
  from public;
grant execute on function public.fetch_collections_report(timestamptz, uuid[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- record_opening_balance_adjustment — 089 signature with p_reference_number
-- is unchanged. Verification.
-- ---------------------------------------------------------------------------

do $$
begin
  if not has_function_privilege(
       'authenticated', 'public.inventory_stock_selling_value(uuid)', 'EXECUTE'
     ) then
    raise exception '093: authenticated cannot execute inventory_stock_selling_value()';
  end if;
  if not has_function_privilege(
       'authenticated',
       'public.reassign_order_sales_rep(uuid, uuid)',
       'EXECUTE'
     ) then
    raise exception '093: authenticated cannot execute reassign_order_sales_rep()';
  end if;
  if not has_function_privilege(
       'authenticated',
       'public.correct_completed_payment(uuid, numeric, text, jsonb, text, text, text, uuid)',
       'EXECUTE'
     ) then
    raise exception '093: authenticated cannot execute correct_completed_payment()';
  end if;
end $$;
