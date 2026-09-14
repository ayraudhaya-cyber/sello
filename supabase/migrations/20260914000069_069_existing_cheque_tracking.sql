-- 069: Existing (pre-Sello) cheques — tracking-only onboarding
--
-- Historical instruments brought into Sello for operational tracking.
-- NEVER create payments, apply financials, or change customer balances.
-- Normal create_cheque / visit cheque-received path is unchanged (source=sello).

-- ---------------------------------------------------------------------------
-- Marker
-- ---------------------------------------------------------------------------

alter table public.cheques
  add column if not exists source text not null default 'sello';

alter table public.cheques
  drop constraint if exists cheques_source_allowed;

alter table public.cheques
  add constraint cheques_source_allowed
  check (source in ('sello', 'existing'));

comment on column public.cheques.source is
  'sello = recorded through normal Sello flows; existing = pre-Sello historical '
  'instrument for tracking only (no payment / no balance apply on create).';

create index if not exists cheques_company_source_status_idx
  on public.cheques (company_id, source, status)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- create_existing_cheque — tracking only
-- ---------------------------------------------------------------------------

create or replace function public.create_existing_cheque(
  p_customer_id uuid,
  p_amount numeric,
  p_bank_name text,
  p_cheque_number text,
  p_holder_name text,
  p_cheque_date date,
  p_status text,
  p_collection_date date default null,
  p_deposit_date date default null,
  p_clearance_date date default null,
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
  branch uuid;
  cheque_id uuid;
  label text;
  status_in text := lower(trim(coalesce(p_status, '')));
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  -- Hub onboarding only — not Sales Rep field capture.
  if not public.can_manage_cheque_clearance() then
    raise exception 'Only Owner or Manager can add existing cheques.';
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

  if status_in not in (
    'awaiting_collection', 'collected', 'deposited', 'cleared'
  ) then
    raise exception
      'Existing cheque status must be awaiting collection, collected, deposited, or cleared.';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id
      and c.company_id = company
      and c.deleted_at is null
  ) then
    raise exception 'Customer not found.';
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
    source,
    payment_id,
    applied_ar_amount,
    applied_wallet_amount,
    balance_applied_at,
    balance_reversed_at,
    collected_at,
    collected_by,
    deposited_at,
    deposited_by,
    cleared_at,
    cleared_by,
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
    case
      when status_in in ('collected', 'deposited', 'cleared')
        then p_collection_date
      else null
    end,
    nullif(trim(coalesce(p_photo_path, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    status_in,
    'existing',
    null,
    0,
    0,
    null,
    null,
    case
      when status_in in ('collected', 'deposited', 'cleared')
        and p_collection_date is not null
        then p_collection_date::timestamptz
      else null
    end,
    case
      when status_in in ('collected', 'deposited', 'cleared')
        and p_collection_date is not null
        then emp
      else null
    end,
    case
      when status_in in ('deposited', 'cleared')
        and p_deposit_date is not null
        then p_deposit_date::timestamptz
      else null
    end,
    case
      when status_in in ('deposited', 'cleared')
        and p_deposit_date is not null
        then emp
      else null
    end,
    case
      when status_in = 'cleared'
        and p_clearance_date is not null
        then p_clearance_date::timestamptz
      else null
    end,
    case
      when status_in = 'cleared'
        and p_clearance_date is not null
        then emp
      else null
    end,
    emp,
    emp
  )
  returning id into cheque_id;

  perform public._log_cheque_status(
    cheque_id,
    company,
    null,
    status_in,
    emp,
    'Existing cheque added'
  );

  return cheque_id;
end;
$$;

revoke all on function public.create_existing_cheque(
  uuid, numeric, text, text, text, date, text, date, date, date, text, text
) from public;
grant execute on function public.create_existing_cheque(
  uuid, numeric, text, text, text, date, text, date, date, date, text, text
) to authenticated;

comment on function public.create_existing_cheque(
  uuid, numeric, text, text, text, date, text, date, date, date, text, text
) is
  'Import a pre-Sello cheque for tracking. Never creates a payment or applies balances.';

-- ---------------------------------------------------------------------------
-- Bounce: historical tracking-only may mark bounced without inventing a reverse
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

  from_status := ch.status;

  -- Tracking-only existing cheque: status change only — never invent AR/wallet.
  if ch.source = 'existing'
     and ch.payment_id is null
     and ch.balance_applied_at is null then
    update public.cheques
    set
      status = 'bounced',
      bounced_at = timezone('utc', now()),
      bounced_by = emp,
      bounce_reason = nullif(trim(coalesce(p_reason, '')), ''),
      updated_by = emp
    where id = p_cheque_id;

    perform public._log_cheque_status(
      p_cheque_id,
      company,
      from_status,
      'bounced',
      emp,
      coalesce(
        nullif(trim(coalesce(p_reason, '')), ''),
        'Historical cheque marked bounced — no Sello payment to reverse'
      )
    );

    return p_cheque_id;
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
-- Dashboard: pending approval must not include tracking-only existing cheques
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
          and payment_id is not null
          and coalesce(source, 'sello') = 'sello'
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
          and balance_reversed_at is null
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
