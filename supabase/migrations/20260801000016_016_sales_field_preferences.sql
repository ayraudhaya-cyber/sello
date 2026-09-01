-- =============================================================================
-- 016 — Sales field preferences (outstanding balances visibility)
--
-- Company setting that gates whether Sales Reps can see customer outstanding
-- balances on Home, visits, and related field surfaces.
-- =============================================================================

alter table public.company_settings
  add column if not exists sales_reps_can_view_outstanding_balances
    boolean not null default true;

comment on column public.company_settings.sales_reps_can_view_outstanding_balances is
  'When true, Sales Reps may see outstanding balances (collections card, visit meta).';
