-- =============================================================================
-- 104 — Give a cheque to someone else
--
-- An in-hand customer cheque can be handed to a distributor or any other
-- person instead of being taken to the bank. The customer balance is already
-- applied and does not change. After this, Sello does not deposit, clear,
-- bounce, or cancel the cheque.
-- =============================================================================

alter table public.cheques
  add column if not exists given_to_name text,
  add column if not exists given_on date,
  add column if not exists given_at timestamptz,
  add column if not exists given_by uuid references public.employees (id) on delete set null,
  add column if not exists given_note text;

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
      'given'
    )
  );

alter table public.cheques
  drop constraint if exists cheques_given_to_name_not_blank;

alter table public.cheques
  add constraint cheques_given_to_name_not_blank
  check (given_to_name is null or length(trim(given_to_name)) > 0);

alter table public.cheques
  drop constraint if exists cheques_given_note_not_blank;

alter table public.cheques
  add constraint cheques_given_note_not_blank
  check (given_note is null or length(trim(given_note)) > 0);

alter table public.cheques
  drop constraint if exists cheques_given_when_handed_over;

alter table public.cheques
  add constraint cheques_given_when_handed_over check (
    status <> 'given'
    or (
      given_to_name is not null
      and given_on is not null
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
      'given'
    )
  );

comment on column public.cheques.given_to_name is
  'Person who received this customer cheque. Set when status is given.';

create or replace function public.prevent_given_cheque_status_change()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'given' and new.status is distinct from 'given' then
    raise exception
      'This cheque was given to someone else. Sello does not change it after that.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cheques_keep_given_status on public.cheques;
create trigger trg_cheques_keep_given_status
before update of status on public.cheques
for each row execute function public.prevent_given_cheque_status_change();

create or replace function public.give_cheque(
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
    raise exception 'Only Owner or Manager can give a cheque to someone else.';
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

  if ch.status = 'given' then
    return ch.id;
  end if;

  if ch.status <> 'collected' then
    raise exception 'Only a cheque in hand can be given to someone else.';
  end if;

  if ch.balance_applied_at is null
     and not (
       coalesce(ch.source, 'sello') = 'existing'
       and ch.payment_id is null
     ) then
    raise exception 'Approve this cheque before giving it to someone else.';
  end if;

  update public.cheques
  set
    status = 'given',
    given_to_name = recipient,
    given_on = p_given_on,
    given_at = timezone('utc', now()),
    given_by = emp,
    given_note = note,
    updated_by = emp
  where id = p_cheque_id;

  perform public._log_cheque_status(
    p_cheque_id,
    company,
    'collected',
    'given',
    emp,
    coalesce(note, 'Given to ' || recipient)
  );

  return p_cheque_id;
end;
$$;

revoke all on function public.give_cheque(uuid, text, date, text) from public;
grant execute on function public.give_cheque(uuid, text, date, text) to authenticated;
