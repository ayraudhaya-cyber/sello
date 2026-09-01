-- =============================================================================
-- 049 — Claim a test SMS through the existing outbound dispatch ledger
--
-- Owner / Manager (and Administrator) may send a configuration test. Each
-- test creates a unique outbound event so production order/collection
-- idempotency is unchanged. Sender ID still comes from this tenant only.
-- =============================================================================

create or replace function public.claim_test_outbound_sms_dispatch(
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
  v_role text;
  v_sender text;
  v_sms_enabled boolean;
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

  select
    nullif(trim(cs.sms_sender_id), ''),
    coalesce(
      (cs.outbound_notification_policies #>> '{channels,sms}')::boolean,
      true
    )
  into v_sender, v_sms_enabled
  from public.company_settings cs
  where cs.company_id = v_company_id;

  if v_sms_enabled is not true then
    return jsonb_build_object('ok', false, 'reason', 'sms_disabled');
  end if;

  if v_sender is null then
    return jsonb_build_object('ok', false, 'reason', 'missing_sender_id');
  end if;

  insert into public.outbound_notification_events (
    company_id,
    event_type,
    reference_type,
    reference_id
  ) values (
    v_company_id,
    'sms_test',
    'sms_test',
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
    'sms_test',
    nullif(trim(p_address), ''),
    'prepared',
    coalesce(p_payload, '{}'::jsonb)
  )
  returning id into v_dispatch_id;

  return jsonb_build_object(
    'ok', true,
    'dispatch_id', v_dispatch_id,
    'sender_id', v_sender
  );
end;
$$;

comment on function public.claim_test_outbound_sms_dispatch(text, jsonb) is
  'Creates a unique test SMS dispatch for this tenant and returns this tenant''s Sender ID.';

grant execute on function public.claim_test_outbound_sms_dispatch(text, jsonb)
  to authenticated;
