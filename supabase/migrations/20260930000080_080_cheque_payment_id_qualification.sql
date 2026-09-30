-- =============================================================================
-- 080 — Qualify cheque collection payment_id
--
-- _create_cheque_collection_payment stored the new payments.id in a variable
-- also named payment_id, then wrote:
--   update cheques set payment_id = payment_id
-- PostgreSQL cannot tell the column from the variable, so Collect fails
-- before allocations or balances are applied. The whole RPC rolls back.
--
-- The right-hand side is the new payment. The left-hand side is
-- cheques.payment_id. Qualify the variable. Do not rename columns.
-- =============================================================================

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

  -- Already linked. Collecting again must not create a second payment.
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
    payment_id = _create_cheque_collection_payment.payment_id,
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

do $$
declare
  body text;
begin
  body := pg_get_functiondef(
    'public._create_cheque_collection_payment(uuid, jsonb, text)'::regprocedure
  );

  if body ~ 'payment_id[[:space:]]*=[[:space:]]*payment_id([^.]|$)' then
    raise exception
      '080: cheques.payment_id assignment is still ambiguous';
  end if;

  if position(
    'payment_id = _create_cheque_collection_payment.payment_id' in body
  ) = 0 then
    raise exception
      '080: new payment id is not written to cheques.payment_id';
  end if;
end;
$$;
