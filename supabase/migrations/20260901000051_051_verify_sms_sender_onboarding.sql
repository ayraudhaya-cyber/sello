-- =============================================================================
-- 051 — Owner onboarding Sender ID verification
--
-- Tenants still cannot UPDATE company_settings.sms_sender_id while
-- sms_sender_id_editable is false (migration 050). Verification sends a test
-- SMS with a *candidate* Sender ID; persistence happens only after Text.lk
-- accepts, via a service-role RPC. Sello operators can still set
-- sms_sender_id in SQL. No new tables.
-- =============================================================================

create or replace function public.claim_verify_sms_sender_dispatch(
  p_address text,
  p_sender_id text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_role text;
  v_candidate text;
  v_existing text;
  v_editable boolean;
  v_event_id uuid;
  v_dispatch_id uuid;
begin
  v_company_id := public.current_company_id();
  if v_company_id is null then
    return jsonb_build_object('ok', false, 'reason', 'session_missing');
  end if;

  v_role := coalesce(public.current_role_code(), '');
  if v_role not in ('owner', 'manager', 'administrator') then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;

  v_candidate := nullif(trim(p_sender_id), '');
  if v_candidate is null or v_candidate !~ '^[A-Za-z0-9]{3,11}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_sender_id');
  end if;

  select
    nullif(trim(cs.sms_sender_id), ''),
    coalesce(cs.sms_sender_id_editable, false)
  into v_existing, v_editable
  from public.company_settings cs
  where cs.company_id = v_company_id;

  if v_existing is not null
     and v_existing is distinct from v_candidate
     and not v_editable then
    return jsonb_build_object('ok', false, 'reason', 'sender_id_locked');
  end if;

  insert into public.outbound_notification_events (
    company_id,
    event_type,
    reference_type,
    reference_id
  ) values (
    v_company_id,
    'sms_sender_verify',
    'sms_sender_verify',
    gen_random_uuid()
  )
  returning id into v_event_id;

  insert into public.outbound_notification_dispatches (
    event_id,
    channel,
    recipient_kind,
    recipient_key,
    address,
    status,
    payload
  ) values (
    v_event_id,
    'sms',
    'hub',
    'sms_sender_verify',
    nullif(trim(p_address), ''),
    'prepared',
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
      'purpose', 'verify_sender',
      'candidate_sender_id', v_candidate
    )
  )
  returning id into v_dispatch_id;

  return jsonb_build_object(
    'ok', true,
    'dispatch_id', v_dispatch_id,
    'sender_id', v_candidate
  );
end;
$$;

comment on function public.claim_verify_sms_sender_dispatch(text, text, jsonb) is
  'Creates a verification SMS dispatch using a candidate Sender ID. Does not write company_settings.';

grant execute on function public.claim_verify_sms_sender_dispatch(text, text, jsonb)
  to authenticated;

-- Service-role only. The Edge Function calls this after Text.lk accepts.
-- JWT clients cannot invoke it, so they cannot skip the provider check.
create or replace function public.activate_verified_sms_sender_id(
  p_dispatch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_type text;
  v_status text;
  v_sender text;
  v_updated integer := 0;
begin
  select
    e.company_id,
    e.event_type,
    d.status,
    nullif(trim(d.payload ->> 'candidate_sender_id'), '')
  into v_company_id, v_type, v_status, v_sender
  from public.outbound_notification_dispatches d
  join public.outbound_notification_events e on e.id = d.event_id
  where d.id = p_dispatch_id
    and d.channel = 'sms';

  if v_company_id is null then
    return jsonb_build_object('ok', false, 'reason', 'dispatch_not_found');
  end if;

  if v_type is distinct from 'sms_sender_verify' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_event');
  end if;

  if v_status is distinct from 'sent' then
    return jsonb_build_object('ok', false, 'reason', 'not_sent');
  end if;

  if v_sender is null or v_sender !~ '^[A-Za-z0-9]{3,11}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_sender_id');
  end if;

  -- auth.uid() is null for service_role, so the 050 trigger allows this write.
  -- Never flip sms_sender_id_editable. Never overwrite a different locked ID.
  update public.company_settings cs
  set sms_sender_id = v_sender
  where cs.company_id = v_company_id
    and (
      nullif(trim(cs.sms_sender_id), '') is null
      or cs.sms_sender_id = v_sender
      or coalesce(cs.sms_sender_id_editable, false)
    );

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    return jsonb_build_object('ok', false, 'reason', 'sender_id_locked');
  end if;

  return jsonb_build_object('ok', true, 'sender_id', v_sender);
end;
$$;

comment on function public.activate_verified_sms_sender_id(uuid) is
  'Persists a Sender ID only after a verification SMS was marked sent. Service role only.';

revoke all on function public.activate_verified_sms_sender_id(uuid) from public;
revoke all on function public.activate_verified_sms_sender_id(uuid) from anon, authenticated;
grant execute on function public.activate_verified_sms_sender_id(uuid) to service_role;
