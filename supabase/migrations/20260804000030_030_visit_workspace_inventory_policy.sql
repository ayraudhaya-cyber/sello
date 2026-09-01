-- Visit workspace foundations: inventory timing preference + visit signature write path.
-- Cheque remains a collection arrangement in the app (reference / follow-up visit)
-- until payments.method allow-list is extended in a dedicated payments migration.

alter table public.company_settings
  add column if not exists inventory_movement_policy text
    not null default 'deduct_on_invoice';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'company_settings_inventory_movement_policy_allowed'
  ) then
    alter table public.company_settings
      add constraint company_settings_inventory_movement_policy_allowed
      check (
        inventory_movement_policy in (
          'reserve_on_order',
          'deduct_on_approval',
          'deduct_on_invoice',
          'deduct_on_dispatch'
        )
      );
  end if;
end $$;

comment on column public.company_settings.inventory_movement_policy is
  'When stock is reduced for a sale: reserve_on_order | deduct_on_approval | deduct_on_invoice | deduct_on_dispatch. Enforcement in complete_sales_order / adjust_inventory lands in a follow-up migration; column is the product seam.';
