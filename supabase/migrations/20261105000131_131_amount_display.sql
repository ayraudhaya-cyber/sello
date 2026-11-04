-- =============================================================================
-- 131 — Summary amount display
--
-- Owners choose how KPI and summary amounts are written: the full figure,
-- lakhs, or millions. Detail screens, tables, and documents stay exact.
-- =============================================================================

alter table public.company_settings
  add column if not exists amount_display text not null default 'exact';

alter table public.company_settings
  drop constraint if exists company_settings_amount_display_allowed;

alter table public.company_settings
  add constraint company_settings_amount_display_allowed
  check (amount_display in ('exact', 'lakhs', 'millions'));

comment on column public.company_settings.amount_display is
  'How summary and KPI amounts are written: exact, lakhs, or millions. Detail screens always show the full amount.';
