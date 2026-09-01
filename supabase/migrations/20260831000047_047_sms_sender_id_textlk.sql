-- =============================================================================
-- 047 — Tenant SMS Sender ID + server-side SMS dispatch ledger
--
-- Text.lk credentials stay in Edge Function secrets. This migration only
-- stores the public Sender ID per tenant and lets the SMS function claim /
-- finalize rows in outbound_notification_dispatches.
-- =============================================================================

alter table public.company_settings
  add column if not exists sms_sender_id text;

alter table public.company_settings
  drop constraint if exists company_settings_sms_sender_id_format;

alter table public.company_settings
  add constraint company_settings_sms_sender_id_format
  check (
    sms_sender_id is null
    or sms_sender_id ~ '^[A-Z0-9]{3,11}$'
  );

comment on column public.company_settings.sms_sender_id is
  'Approved SMS Sender ID shown to customers. Text.lk API token is never stored here.';

-- Allow 'sent' so automatic SMS can be distinguished from device-prefill 'prepared'.
alter table public.outbound_notification_dispatches
  drop constraint if exists outbound_notification_dispatches_status_allowed;

alter table public.outbound_notification_dispatches
  add constraint outbound_notification_dispatches_status_allowed check (
    status in ('prepared', 'skipped', 'failed', 'sent')
  );

-- ---------------------------------------------------------------------------
-- Only Owner / Administrator may change the Sender ID.
-- ---------------------------------------------------------------------------

create or replace function public.can_edit_sms_sender_id()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role_code(), '') in (
    'owner',
    'administrator'
  );
$$;

comment on function public.can_edit_sms_sender_id() is
  'Matches IAM: Owner/Administrator can edit settings; Manager is view-only; Sales cannot.';

grant execute on function public.can_edit_sms_sender_id() to authenticated;

create or replace function public.company_settings_guard_sms_sender_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.sms_sender_id is distinct from new.sms_sender_id
     and not public.can_edit_sms_sender_id() then
    raise exception 'Only an Owner can change the SMS Sender ID.';
  end if;
  return new;
end;
$$;

drop trigger if exists company_settings_guard_sms_sender_id
  on public.company_settings;

create trigger company_settings_guard_sms_sender_id
  before update on public.company_settings
  for each row
  execute function public.company_settings_guard_sms_sender_id();

-- ---------------------------------------------------------------------------
-- Claim a unique SMS dispatch for this tenant, returning *this* tenant's
-- Sender ID. The client cannot supply another company's Sender ID.
-- ---------------------------------------------------------------------------

create or replace function public.claim_outbound_sms_dispatch(
  p_event_id uuid,
  p_recipient_kind text,
  p_recipient_key text,
  p_address text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_sender text;
  v_dispatch_id uuid;
  v_existing uuid;
  v_existing_status text;
  v_count integer := 0;
begin
  v_company_id := public.current_company_id();
  if v_company_id is null then
    return jsonb_build_object('ok', false, 'reason', 'session_missing');
  end if;

  if not exists (
    select 1
    from public.outbound_notification_events e
    where e.id = p_event_id
      and e.company_id = v_company_id
  ) then
    return jsonb_build_object('ok', false, 'reason', 'event_not_found');
  end if;

  select nullif(trim(cs.sms_sender_id), '')
  into v_sender
  from public.company_settings cs
  where cs.company_id = v_company_id;

  if v_sender is null then
    return jsonb_build_object('ok', false, 'reason', 'missing_sender_id');
  end if;

  select d.id, d.status
  into v_existing, v_existing_status
  from public.outbound_notification_dispatches d
  where d.event_id = p_event_id
    and d.channel = 'sms'
    and d.recipient_kind = p_recipient_kind
    and d.recipient_key = p_recipient_key;

  if v_existing is not null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'already_sent',
      'dispatch_id', v_existing,
      'status', v_existing_status
    );
  end if;

  insert into public.outbound_notification_dispatches (
    event_id,
    channel,
    recipient_kind,
    recipient_key,
    address,
    status,
    payload
  ) values (
    p_event_id,
    'sms',
    p_recipient_kind,
    p_recipient_key,
    nullif(trim(p_address), ''),
    'prepared',
    coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (event_id, channel, recipient_kind, recipient_key) do nothing
  returning id into v_dispatch_id;

  get diagnostics v_count = row_count;

  if v_count = 0 or v_dispatch_id is null then
    return jsonb_build_object('ok', false, 'reason', 'already_sent');
  end if;

  return jsonb_build_object(
    'ok', true,
    'dispatch_id', v_dispatch_id,
    'sender_id', v_sender
  );
end;
$$;

comment on function public.claim_outbound_sms_dispatch(uuid, text, text, text, jsonb) is
  'Inserts a unique SMS dispatch for the caller''s company and returns that tenant''s Sender ID.';

grant execute on function public.claim_outbound_sms_dispatch(uuid, text, text, text, jsonb)
  to authenticated;

create or replace function public.finalize_outbound_sms_dispatch(
  p_dispatch_id uuid,
  p_status text,
  p_payload jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_updated integer := 0;
begin
  v_company_id := public.current_company_id();
  if v_company_id is null then
    return false;
  end if;

  if p_status not in ('sent', 'failed') then
    return false;
  end if;

  update public.outbound_notification_dispatches d
  set
    status = p_status,
    payload = coalesce(d.payload, '{}'::jsonb) || coalesce(p_payload, '{}'::jsonb)
  from public.outbound_notification_events e
  where d.id = p_dispatch_id
    and d.event_id = e.id
    and e.company_id = v_company_id
    and d.channel = 'sms';

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

comment on function public.finalize_outbound_sms_dispatch(uuid, text, jsonb) is
  'Marks an SMS dispatch sent or failed. Scoped to the caller''s company.';

grant execute on function public.finalize_outbound_sms_dispatch(uuid, text, jsonb)
  to authenticated;
