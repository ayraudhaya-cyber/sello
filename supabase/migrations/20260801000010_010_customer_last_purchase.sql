-- =============================================================================
-- Migration 010 — Customer last_purchase_at (Orders-ready)
--
-- Nullable until sales orders start writing purchase timestamps.
-- =============================================================================

alter table public.customers
  add column if not exists last_purchase_at timestamptz;

create index if not exists customers_company_last_purchase_idx
  on public.customers (company_id, last_purchase_at desc nulls last)
  where deleted_at is null;

comment on column public.customers.last_purchase_at is
  'Most recent completed purchase timestamp. Populated by Orders; null until then.';
