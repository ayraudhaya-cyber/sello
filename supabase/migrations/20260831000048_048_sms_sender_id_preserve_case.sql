-- =============================================================================
-- 048 — Preserve Text.lk Sender ID casing
--
-- Approved IDs are registered exactly as shown in Text.lk (e.g. NamsonLanka).
-- Do not force uppercase.
-- =============================================================================

alter table public.company_settings
  drop constraint if exists company_settings_sms_sender_id_format;

alter table public.company_settings
  add constraint company_settings_sms_sender_id_format
  check (
    sms_sender_id is null
    or sms_sender_id ~ '^[A-Za-z0-9]{3,11}$'
  );

comment on column public.company_settings.sms_sender_id is
  'Approved SMS Sender ID, stored with the same casing as Text.lk. API token is never stored here.';
