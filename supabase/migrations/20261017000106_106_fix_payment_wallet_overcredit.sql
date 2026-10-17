-- =============================================================================
-- 106 — Prevent collections from being duplicated into customer wallet credit
--
-- A non-wallet collection reduces current_balance by the amount that can pay
-- the customer's AR. Only the amount beyond that AR is genuine wallet credit.
-- The previous function compared against explicit allocations instead. When a
-- collection had no allocation (or only partial allocations), the same money
-- could reduce outstanding and also be credited to the wallet.
-- =============================================================================

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
  -- Wallet credit is only the part left after reducing actual outstanding.
  -- Explicit allocations describe documents, not whether cash is an overpay.
  overpay := greatest(payment_row.amount - ar_reduction, 0);
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
    applied_wallet_amount =
      greatest(coalesce(wallet_after, wallet_before) - wallet_before, 0),
    applied_wallet_debit =
      greatest(wallet_before - coalesce(wallet_after, wallet_before), 0),
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

-- Repair snapshot-backed overcredits created after migration 093. This only
-- auto-repairs a customer when the erroneous credit is still present in their
-- wallet. If it has already been spent, no automatic historical rewrite is
-- attempted because the related allocations require an explicit correction.
do $$
declare
  repair record;
begin
  for repair in
    select
      p.customer_id,
      sum(
        p.applied_wallet_amount
        - greatest(p.amount - p.applied_ar_amount, 0)
      )::numeric(14, 2) as excess
    from public.payments p
    where p.status = 'completed'
      and p.deleted_at is null
      and p.method <> 'wallet'
      and p.applied_ar_amount > 0
      and p.applied_wallet_amount
        > greatest(p.amount - p.applied_ar_amount, 0) + 0.001
    group by p.customer_id
  loop
    if exists (
      select 1
      from public.customers c
      where c.id = repair.customer_id
        and c.wallet_balance + 0.001 >= repair.excess
    ) then
      update public.customers
      set
        wallet_balance = greatest(wallet_balance - repair.excess, 0),
        updated_at = timezone('utc', now())
      where id = repair.customer_id;

      update public.payments p
      set applied_wallet_amount =
        greatest(p.amount - p.applied_ar_amount, 0)
      where p.customer_id = repair.customer_id
        and p.status = 'completed'
        and p.deleted_at is null
        and p.method <> 'wallet'
        and p.applied_ar_amount > 0
        and p.applied_wallet_amount
          > greatest(p.amount - p.applied_ar_amount, 0) + 0.001;
    end if;
  end loop;
end $$;
