-- =============================================================================
-- 105 — After a cheque is given to someone else
--
-- I have it back: the paper is in hand again. The customer balance stays.
-- Return to customer: the cheque is given back to the customer and what they
-- owe goes back up, once, through the same reversal as a bank return.
-- Who received it can be corrected while the cheque is still Given.
-- =============================================================================

alter table public.cheques
  add column if not exists returned_at timestamptz,
  add column if not exists returned_by uuid references public.employees (id) on delete set null,
  add column if not exists return_reason text;

alter table public.cheques
  drop constraint if exists cheques_return_reason_not_blank;

alter table public.cheques
  add constraint cheques_return_reason_not_blank
  check (return_reason is null or length(trim(return_reason)) > 0);

alter table public.cheques
  drop constraint if exists cheques_status_allowed;

alter table public.cheques
  add constraint cheques_status_allowed check (
    status in (
      'awaiting_collection',
      'collected',
      'deposited',
      'cleared',
      'bounced',
      'cancelled',
      'given',
      'returned_to_customer'
    )
  );

alter table public.cheque_status_events
  drop constraint if exists cheque_status_events_to_status_allowed;

alter table public.cheque_status_events
  add constraint cheque_status_events_to_status_allowed check (
    to_status in (
      'awaiting_collection',
      'collected',
      'deposited',
      'cleared',
      'bounced',
      'cancelled',
      'given',
      'returned_to_customer'
    )
  );

create or replace function public.prevent_given_cheque_status_change()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'given'
     and new.status is distinct from 'given'
     and new.status not in ('collected', 'returned_to_customer') then
    raise exception
      'This cheque was given to someone else. Bring it back in hand, or return it to the customer.';
  end if;
  return new;
end;
$$;

create or replace function public.recall_given_cheque(p_cheque_id uuid)
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
    raise exception 'Only Owner or Manager can bring a cheque back.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'collected' and ch.given_at is null then
    return ch.id;
  end if;

  if ch.status <> 'given' then
    raise exception 'Only a cheque you have given to someone else can come back.';
  end if;

  update public.cheques
  set
    status = 'collected',
    given_to_name = null,
    given_on = null,
    given_at = null,
    given_by = null,
    given_note = null,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id,
    company,
    'given',
    'collected',
    emp,
    'Back in hand. Customer balance unchanged.'
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.recall_given_cheque(uuid) from public;
grant execute on function public.recall_given_cheque(uuid) to authenticated;

create or replace function public.return_given_cheque_to_customer(
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
  reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can return a cheque to the customer.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status = 'returned_to_customer' then
    return ch.id;
  end if;

  if ch.status <> 'given' then
    raise exception 'Only a cheque you have given to someone else can be returned to the customer.';
  end if;

  if ch.balance_applied_at is not null then
    perform public._reverse_cheque_collection_ledger(p_cheque_id);
  elsif not (
    coalesce(ch.source, 'sello') = 'existing'
    and ch.payment_id is null
  ) then
    raise exception
      'This cheque has not been applied yet. Bring it back in hand instead.';
  end if;

  update public.cheques
  set
    status = 'returned_to_customer',
    returned_at = timezone('utc', now()),
    returned_by = emp,
    return_reason = reason,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id,
    company,
    'given',
    'returned_to_customer',
    emp,
    coalesce(reason, 'Returned to the customer')
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.return_given_cheque_to_customer(uuid, text) from public;
grant execute on function public.return_given_cheque_to_customer(uuid, text) to authenticated;

create or replace function public.update_given_cheque(
  p_cheque_id uuid,
  p_given_to_name text,
  p_given_on date,
  p_note text default null
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
  recipient text := nullif(trim(coalesce(p_given_to_name, '')), '');
  note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can change who received a cheque.';
  end if;

  if recipient is null then
    raise exception 'Enter who received this cheque.';
  end if;

  if length(recipient) > 120 then
    raise exception 'The name is too long.';
  end if;

  if p_given_on is null then
    raise exception 'Enter the date you gave the cheque.';
  end if;

  select * into ch
  from public.cheques
  where id = p_cheque_id and company_id = company and deleted_at is null
  for update;

  if not found then
    raise exception 'Cheque not found.';
  end if;

  if ch.status <> 'given' then
    raise exception 'Who received this cheque can be changed only while it is given.';
  end if;

  update public.cheques
  set
    given_to_name = recipient,
    given_on = p_given_on,
    given_note = note,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id,
    company,
    'given',
    'given',
    emp,
    'Corrected who received it: ' || recipient
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.update_given_cheque(uuid, text, date, text) from public;
grant execute on function public.update_given_cheque(uuid, text, date, text) to authenticated;
