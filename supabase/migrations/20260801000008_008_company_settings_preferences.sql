-- =============================================================================
-- 008 — Company settings preferences (Business + Inventory Phase 1)
--
-- Extends company_settings with operational preferences used by Products and
-- future modules. Ensures every company has a settings row and can update it
-- under RLS.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Columns
-- -----------------------------------------------------------------------------

alter table public.company_settings
  add column if not exists currency_position text not null default 'before',
  add column if not exists financial_year_start_month smallint not null default 1,
  add column if not exists default_tax_mode text not null default 'exclusive',
  add column if not exists default_reorder_level integer not null default 10,
  add column if not exists default_product_status text not null default 'active',
  add column if not exists allow_negative_stock boolean not null default false,
  add column if not exists enable_low_stock_alert boolean not null default true;

alter table public.company_settings
  drop constraint if exists company_settings_currency_position_check,
  drop constraint if exists company_settings_fy_start_month_check,
  drop constraint if exists company_settings_tax_mode_check,
  drop constraint if exists company_settings_reorder_level_check,
  drop constraint if exists company_settings_product_status_check;

alter table public.company_settings
  add constraint company_settings_currency_position_check
    check (currency_position in ('before', 'after')),
  add constraint company_settings_fy_start_month_check
    check (financial_year_start_month between 1 and 12),
  add constraint company_settings_tax_mode_check
    check (default_tax_mode in ('exclusive', 'inclusive', 'none')),
  add constraint company_settings_reorder_level_check
    check (default_reorder_level >= 0),
  add constraint company_settings_product_status_check
    check (default_product_status in ('active', 'inactive'));

comment on table public.company_settings is
  'Branding, localization, and operational preferences per company.';
comment on column public.company_settings.currency_position is
  'Whether the currency symbol appears before or after amounts.';
comment on column public.company_settings.financial_year_start_month is
  'Calendar month (1–12) when the financial year begins.';
comment on column public.company_settings.default_tax_mode is
  'Default tax treatment for pricing: exclusive, inclusive, or none.';
comment on column public.company_settings.default_reorder_level is
  'Default reorder level applied when creating a new product.';
comment on column public.company_settings.default_product_status is
  'Default active/inactive status for newly created products.';
comment on column public.company_settings.allow_negative_stock is
  'When true, stock quantities may go below zero.';
comment on column public.company_settings.enable_low_stock_alert is
  'When true, surface low-stock alerts based on reorder level.';

-- -----------------------------------------------------------------------------
-- Backfill missing settings rows
-- -----------------------------------------------------------------------------

insert into public.company_settings (
  company_id,
  currency,
  timezone,
  locale,
  primary_color,
  secondary_color,
  currency_position,
  financial_year_start_month,
  default_tax_mode,
  default_reorder_level,
  default_product_status,
  allow_negative_stock,
  enable_low_stock_alert
)
select
  c.id,
  'USD',
  'UTC',
  'en-US',
  '#9619F1',
  '#4237E7',
  'before',
  1,
  'exclusive',
  10,
  'active',
  false,
  true
from public.companies c
where not exists (
  select 1
  from public.company_settings s
  where s.company_id = c.id
);

-- -----------------------------------------------------------------------------
-- RLS: allow employees to update (and insert if missing) their company settings
-- -----------------------------------------------------------------------------

drop policy if exists "company_settings_update_own" on public.company_settings;
create policy "company_settings_update_own"
  on public.company_settings
  for update
  to authenticated
  using (company_id = public.current_company_id())
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );

drop policy if exists "company_settings_insert_own" on public.company_settings;
create policy "company_settings_insert_own"
  on public.company_settings
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );
