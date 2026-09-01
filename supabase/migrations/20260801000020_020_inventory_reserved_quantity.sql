-- =============================================================================
-- 020 — Inventory operational polish
--
-- Reserved quantity seam (Available = on-hand − reserved) for future order
-- holds / allocations. Valuation continues to use products.cost_price.
-- =============================================================================

alter table public.inventory
  add column if not exists reserved_quantity numeric(14, 3) not null default 0;

alter table public.inventory
  drop constraint if exists inventory_reserved_non_negative;

alter table public.inventory
  add constraint inventory_reserved_non_negative
  check (reserved_quantity >= 0);

comment on column public.inventory.reserved_quantity is
  'Quantity held for open commitments (future). Available = quantity - reserved_quantity.';

comment on column public.inventory.quantity is
  'On-hand quantity at the branch. Manual and sale adjustments go through adjust_inventory.';
