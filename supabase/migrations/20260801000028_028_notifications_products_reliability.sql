-- =============================================================================
-- 028 — Notifications platform: products + reliability categories
-- =============================================================================
-- Extends category vocabulary for Products and Reliability events so the shared
-- business event bus can publish without module-specific notification systems.
-- =============================================================================

alter table public.notifications
  drop constraint if exists notifications_category_allowed;

alter table public.notifications
  add constraint notifications_category_allowed check (
    category in (
      'orders', 'inventory', 'payments', 'customers', 'suppliers', 'products',
      'schedule', 'visits', 'team', 'system', 'intelligence', 'reliability'
    )
  );

alter table public.company_activity_events
  drop constraint if exists company_activity_events_category_allowed;

alter table public.company_activity_events
  add constraint company_activity_events_category_allowed check (
    category in (
      'orders', 'inventory', 'payments', 'customers', 'suppliers', 'products',
      'schedule', 'visits', 'team', 'system', 'intelligence', 'reliability'
    )
  );

alter table public.notification_preferences
  drop constraint if exists notification_preferences_category_allowed;

alter table public.notification_preferences
  add constraint notification_preferences_category_allowed check (
    category in (
      'orders', 'inventory', 'payments', 'customers', 'suppliers', 'products',
      'schedule', 'visits', 'team', 'system', 'intelligence', 'reliability'
    )
  );

-- Seed preference rows for new categories on all active employees.
create or replace function public.ensure_notification_preferences(
  p_employee_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_cat text;
begin
  select company_id into v_company_id
  from public.employees
  where id = p_employee_id
    and deleted_at is null;

  if v_company_id is null then
    return;
  end if;

  foreach v_cat in array array[
    'orders', 'inventory', 'payments', 'customers', 'suppliers', 'products',
    'schedule', 'visits', 'team', 'system', 'intelligence', 'reliability'
  ]
  loop
    insert into public.notification_preferences (
      company_id,
      employee_id,
      category,
      channel_in_app,
      channel_push,
      channel_email,
      channel_sms,
      channel_whatsapp
    )
    values (
      v_company_id,
      p_employee_id,
      v_cat,
      true,
      false,
      false,
      false,
      false
    )
    on conflict (employee_id, category) do nothing;
  end loop;
end;
$$;

comment on function public.ensure_notification_preferences(uuid) is
  'Ensures preference rows for every notification category (incl. products + reliability).';
