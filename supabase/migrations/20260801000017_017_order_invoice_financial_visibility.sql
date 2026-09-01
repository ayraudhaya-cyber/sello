-- =============================================================================
-- 017 — Order & invoice financial visibility policies
--
-- Extensible JSON map of customer financial fields → visibility policy:
--   never | internal_only | customer_copy
--
-- First configured field: outstanding_balance. Wallet / credit fields are
-- reserved in the map for future Order & Invoice Policies without schema churn.
-- =============================================================================

alter table public.company_settings
  add column if not exists financial_visibility_policies jsonb
    not null
    default '{"outstanding_balance":"internal_only"}'::jsonb;

comment on column public.company_settings.financial_visibility_policies is
  'Map of financial field keys to visibility: never, internal_only, customer_copy. '
  'Controls internal vs customer-facing invoice/SMS/WhatsApp/PDF surfaces.';

-- Keep sales_reps_can_view_outstanding_balances (016) as the Sales permission
-- gate when outstanding_balance policy is internal_only.
comment on column public.company_settings.sales_reps_can_view_outstanding_balances is
  'When outstanding_balance visibility is internal_only, Sales Reps may see '
  'balances only if this is true. Ignored when policy is never; implied when '
  'policy is customer_copy.';
