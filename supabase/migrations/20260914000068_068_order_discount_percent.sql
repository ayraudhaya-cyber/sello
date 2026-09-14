-- Migration 068: Order header percentage discount (alongside fixed amount)
--
-- Users may apply discount amount, discount %, or both.
-- Math: percent off subtotal first, then subtract fixed amount.
--
-- Persistence:
--   discount_percent      = raw % entered (0–100)
--   discount_fixed_amount = raw fixed currency entered
--   discount_amount       = resolved combined discount (docs / legacy UI)

alter table public.orders
  add column if not exists discount_percent numeric(5, 2) not null default 0;

alter table public.orders
  add column if not exists discount_fixed_amount numeric(14, 2) not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_discount_percent_range'
  ) then
    alter table public.orders
      add constraint orders_discount_percent_range
        check (discount_percent >= 0 and discount_percent <= 100);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'orders_discount_fixed_amount_non_negative'
  ) then
    alter table public.orders
      add constraint orders_discount_fixed_amount_non_negative
        check (discount_fixed_amount >= 0);
  end if;
end $$;

-- Existing rows: fixed amount lived in discount_amount with percent = 0.
update public.orders
set discount_fixed_amount = discount_amount
where discount_fixed_amount = 0
  and discount_amount > 0
  and discount_percent = 0;

comment on column public.orders.discount_percent is
  'Header discount as a percent of subtotal (0–100). Applied before fixed amount.';

comment on column public.orders.discount_fixed_amount is
  'Header discount as a fixed currency amount. Applied after percent.';

comment on column public.orders.discount_amount is
  'Resolved combined header discount (percent then fixed). Used by documents and legacy display.';
