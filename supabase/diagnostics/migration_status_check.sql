-- =============================================================================
-- Migration status check (paste into Supabase SQL Editor → Run)
--
-- Returns one row per local migration file with applied = true/false based on
-- schema objects those migrations introduce. Not a substitute for
-- supabase_migrations.schema_migrations when using the CLI — this project
-- often applies SQL manually in the dashboard.
-- =============================================================================

with checks as (
  select * from (values
    -- 001
    ('001_initial_foundation_schema',
      to_regclass('public.companies') is not null
      and to_regclass('public.employees') is not null),
    -- 002
    ('002_rls_session_bootstrap',
      exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'current_company_id'
      )),
    -- 003
    ('003_business_provisioning',
      exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'provision_business'
      )),
    -- 004
    ('004_pending_business_onboarding',
      to_regclass('public.pending_business_provisions') is not null),
    -- 005
    ('005_company_subscription_foundation',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'companies'
          and column_name = 'subscription_status'
      )),
    -- 006
    ('006_product_catalog_foundation',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'products'
          and column_name = 'sku'
      )),
    -- 007 (docs-only: comment on existing product_images; no new table/bucket)
    ('007_product_media_foundation',
      to_regclass('public.product_images') is not null
      and exists (
        select 1
        from pg_catalog.pg_description d
        join pg_catalog.pg_class c on c.oid = d.objoid
        join pg_catalog.pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'product_images'
          and d.objsubid = 0
          and d.description ilike '%gallery%'
      )),
    -- 008
    ('008_company_settings_preferences',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'company_settings'
          and column_name = 'enable_low_stock_alert'
      )),
    -- 009 (wallet_balance is the distinguishing column; current_balance is from 001)
    ('009_customer_domain_foundation',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'customers'
          and column_name = 'wallet_balance'
      )),
    -- 010
    ('010_customer_last_purchase',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'customers'
          and column_name = 'last_purchase_at'
      )),
    -- 011
    ('011_orders_domain_foundation',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'orders'
          and column_name = 'payment_status'
      )),
    -- 012
    ('012_payments_domain_foundation',
      to_regclass('public.payments') is not null),
    -- 013
    ('013_inventory_domain_foundation',
      to_regclass('public.stock_movements') is not null),
    -- 014
    ('014_employees_domain_foundation',
      to_regclass('public.employee_assignments') is not null
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'employees'
          and column_name = 'employment_status'
      )),
    -- 014 trigger specifically (re-run failure point)
    ('014_employee_assignments_trigger',
      exists (
        select 1 from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'employee_assignments'
          and t.tgname = 'trg_employee_assignments_set_updated_at'
          and not t.tgisinternal
      )),
    -- 015
    ('015_suppliers_domain_foundation',
      to_regclass('public.suppliers') is not null),
    -- 016
    ('016_sales_field_preferences',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'company_settings'
          and column_name = 'sales_reps_can_view_outstanding_balances'
      )),
    -- 018
    ('018_product_configurable_fields',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'products'
          and column_name = 'attributes'
      )
      and to_regclass('public.company_product_fields') is not null
      and to_regclass('public.product_field_definitions') is not null),
    -- 019
    ('019_orders_operational_completion',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'orders'
          and column_name = 'offline_client_id'
      )
      and exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'archive_order'
      )),
    -- 020
    ('020_inventory_reserved_quantity',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'inventory'
          and column_name = 'reserved_quantity'
      )),
    -- 021
    ('021_product_suppliers_foundation',
      exists (
        select 1 from information_schema.tables
        where table_schema = 'public'
          and table_name = 'product_suppliers'
      )),
    -- 022
    ('022_employees_invite_notes_permissions',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'employees'
          and column_name = 'notes'
      )
      and to_regclass('public.employee_invites') is not null
      and to_regclass('public.role_module_access') is not null),
    -- 023
    ('023_schedule_visits_foundation',
      to_regclass('public.scheduled_visits') is not null
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'customers'
          and column_name = 'next_visit_at'
      )),
    -- 024
    ('024_notifications_activity_foundation',
      to_regclass('public.notifications') is not null
      and to_regclass('public.company_activity_events') is not null
      and to_regclass('public.notification_preferences') is not null),
    -- 025
    ('025_product_details_intelligence',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'product_field_definitions'
          and column_name = 'group_key'
      )
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'company_product_fields'
          and column_name = 'options_override'
      )),
    -- 026
    ('026_customer_visits_foundation',
      to_regclass('public.customer_visits') is not null
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'payments'
          and column_name = 'visit_id'
      )),
    -- 027
    ('027_notifications_platform_evolution',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'notifications'
          and column_name = 'snoozed_until'
      )
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'notification_preferences'
          and column_name = 'channel_whatsapp'
      )
      and exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'ensure_notification_preferences'
      )),
    -- 028
    ('028_notifications_products_reliability',
      exists (
        select 1
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = 'public'
          and t.relname = 'notifications'
          and c.conname = 'notifications_category_allowed'
          and pg_get_constraintdef(c.oid) like '%reliability%'
          and pg_get_constraintdef(c.oid) like '%products%'
      )),
    ('029_iam_permissions_audit_foundation',
      exists (
        select 1
        from information_schema.tables
        where table_schema = 'public'
          and table_name = 'audit_events'
      )
      and exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'role_module_access'
          and column_name = 'can_approve'
      )),
    -- 031
    ('031_subscription_plans_capacity_foundation',
      to_regclass('public.subscription_plans') is not null
      and to_regclass('public.subscription_plan_prices') is not null
      and to_regclass('public.company_subscriptions') is not null
      and exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'check_company_capacity'
      )
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'companies'
          and column_name = 'current_subscription_id'
      )),
    -- 032
    ('032_schedule_route_area_foundation',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'scheduled_visits'
          and column_name = 'area'
      )),
    -- 034
    ('034_company_custom_branding',
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'company_settings'
          and column_name = 'custom_branding_enabled'
      )
      and exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'can_manage_company_branding'
      )),
    -- 035
    ('035_company_settings_admin_view',
      to_regclass('public.company_settings_admin') is not null),
    -- 058
    ('058_employee_login_invite',
      exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'prepare_employee_login_invite'
      )
      and exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'link_employee_auth_user'
      ))
  ) as t(migration, applied)
)
select
  migration,
  case when applied then 'APPLIED' else 'MISSING' end as status
from checks
order by migration;
