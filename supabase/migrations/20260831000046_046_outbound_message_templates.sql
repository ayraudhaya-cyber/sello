-- =============================================================================
-- 046 — V1 outbound message types (buyer vs Owner/Manager templates)
--
-- Splits order confirmation and collection acknowledgement into distinct
-- buyer and hub messages. Existing custom template text is preserved.
-- Share intents remain device prefill (no Business API).
-- =============================================================================

alter table public.company_settings
  alter column outbound_notification_policies set default '{
      "channels": {"whatsapp": true, "sms": true},
      "types": {
        "order_confirmation": {
          "enabled": true,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["customer"]
        },
        "new_order_notification": {
          "enabled": true,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["hub"]
        },
        "collection_acknowledgement": {
          "enabled": true,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["customer"]
        },
        "collection_submitted": {
          "enabled": true,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["hub"]
        },
        "invoice": {
          "enabled": false,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["customer"]
        },
        "receipt": {
          "enabled": false,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["customer"]
        }
      },
      "templates": {}
    }'::jsonb;

comment on column public.company_settings.outbound_notification_policies is
  'Tenant outbound messaging: channels, per-type recipients, document links, and optional message templates.';

create or replace function public._sello_migrate_outbound_v1(p jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v jsonb := coalesce(p, '{}'::jsonb);
  v_types jsonb;
  v_oc jsonb;
  v_ca jsonb;
  v_oc_rec text[];
  v_ca_rec text[];
  v_oc_keep jsonb;
  v_has_hub boolean;
  v_enabled boolean;
begin
  if jsonb_typeof(v) is distinct from 'object' then
    v := '{}'::jsonb;
  end if;

  v_types := coalesce(v -> 'types', '{}'::jsonb);
  if jsonb_typeof(v_types) is distinct from 'object' then
    v_types := '{}'::jsonb;
  end if;

  if not (v_types ? 'new_order_notification') then
    v_oc := coalesce(v_types -> 'order_confirmation', '{}'::jsonb);
    select coalesce(array_agg(elem), '{}')
      into v_oc_rec
    from jsonb_array_elements_text(coalesce(v_oc -> 'recipients', '[]'::jsonb)) elem;

    v_has_hub := 'hub' = any (v_oc_rec);
    v_enabled := coalesce((v_oc ->> 'enabled')::boolean, true);

    v_types := jsonb_set(
      v_types,
      '{new_order_notification}',
      jsonb_build_object(
        'enabled', v_enabled and v_has_hub,
        'whatsapp', coalesce((v_oc ->> 'whatsapp')::boolean, true),
        'sms', coalesce((v_oc ->> 'sms')::boolean, true),
        'include_document_link', coalesce((v_oc ->> 'include_document_link')::boolean, true),
        'recipients', '["hub"]'::jsonb
      ),
      true
    );

    select coalesce(jsonb_agg(to_jsonb(elem)), '["customer"]'::jsonb)
      into v_oc_keep
    from unnest(v_oc_rec) elem
    where elem is distinct from 'hub';

    if v_oc_keep is null or v_oc_keep = '[]'::jsonb then
      v_oc_keep := '["customer"]'::jsonb;
    end if;

    if jsonb_typeof(v_oc) is distinct from 'object' or v_oc = '{}'::jsonb then
      v_oc := jsonb_build_object(
        'enabled', true,
        'whatsapp', true,
        'sms', true,
        'include_document_link', true,
        'recipients', v_oc_keep
      );
    else
      v_oc := jsonb_set(v_oc, '{recipients}', v_oc_keep, true);
    end if;
    v_types := jsonb_set(v_types, '{order_confirmation}', v_oc, true);
  end if;

  if not (v_types ? 'collection_submitted') then
    v_ca := coalesce(v_types -> 'collection_acknowledgement', '{}'::jsonb);
    select coalesce(array_agg(elem), '{}')
      into v_ca_rec
    from jsonb_array_elements_text(coalesce(v_ca -> 'recipients', '[]'::jsonb)) elem;

    v_has_hub := 'hub' = any (v_ca_rec);
    v_enabled := coalesce((v_ca ->> 'enabled')::boolean, true);

    v_types := jsonb_set(
      v_types,
      '{collection_submitted}',
      jsonb_build_object(
        'enabled', v_enabled and v_has_hub,
        'whatsapp', coalesce((v_ca ->> 'whatsapp')::boolean, true),
        'sms', coalesce((v_ca ->> 'sms')::boolean, true),
        'include_document_link', coalesce((v_ca ->> 'include_document_link')::boolean, true),
        'recipients', '["hub"]'::jsonb
      ),
      true
    );

    if jsonb_typeof(v_ca) is distinct from 'object' or v_ca = '{}'::jsonb then
      v_ca := jsonb_build_object(
        'enabled', true,
        'whatsapp', true,
        'sms', true,
        'include_document_link', true,
        'recipients', '["customer"]'::jsonb
      );
    else
      v_ca := jsonb_set(v_ca, '{recipients}', '["customer"]'::jsonb, true);
    end if;
    v_types := jsonb_set(v_types, '{collection_acknowledgement}', v_ca, true);
  end if;

  v := jsonb_set(v, '{types}', v_types, true);
  if not (v ? 'templates') then
    v := jsonb_set(v, '{templates}', '{}'::jsonb, true);
  end if;
  return v;
end;
$$;

update public.company_settings
set outbound_notification_policies =
  public._sello_migrate_outbound_v1(outbound_notification_policies);

drop function public._sello_migrate_outbound_v1(jsonb);
