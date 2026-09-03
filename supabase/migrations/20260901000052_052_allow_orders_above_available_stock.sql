-- Allow Sales Reps to order above recorded available stock (tenant preference).

alter table public.company_settings
  add column if not exists allow_orders_above_available_stock
    boolean not null default false;

comment on column public.company_settings.allow_orders_above_available_stock is
  'When false, Sales Rep quantity controls cannot exceed branch available stock (on-hand minus reserved).';
