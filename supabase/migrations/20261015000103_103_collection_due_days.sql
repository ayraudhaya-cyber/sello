-- =============================================================================
-- 103 — Default collection due days
--
-- Grace period after an order or opening balance is recorded. The still-to-
-- collect report uses this to say "Due in N days" or "Overdue by N days".
-- 0 means payment is due the same day it is recorded.
-- =============================================================================

alter table public.company_settings
  add column if not exists collection_due_days integer not null default 0;

comment on column public.company_settings.collection_due_days is
  'Days after an order or opening balance is recorded before it is due. 0 means due the same day.';

alter table public.company_settings
  drop constraint if exists company_settings_collection_due_days_range;

alter table public.company_settings
  add constraint company_settings_collection_due_days_range
  check (collection_due_days >= 0 and collection_due_days <= 365);
