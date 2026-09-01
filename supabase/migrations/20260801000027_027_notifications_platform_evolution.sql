-- =============================================================================
-- 027 — Notifications platform evolution
--
-- Extends 024: suppliers category, snooze seam, WhatsApp channel preference,
-- activity reference index for entity timelines.
-- =============================================================================

-- Expand category vocabulary (notifications / activity / preferences).
-- Include products + reliability here so this migration stays valid if 028
-- already ran (re-applying a narrower CHECK would violate existing rows).
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
  drop constraint if exists company_activity_category_allowed;
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

-- Future snooze (UI later)
alter table public.notifications
  add column if not exists snoozed_until timestamptz;

comment on column public.notifications.snoozed_until is
  'Future snooze — hide from inbox until this timestamp. Null = not snoozed.';

-- Future WhatsApp channel (delivery not implemented)
alter table public.notification_preferences
  add column if not exists channel_whatsapp boolean not null default false;

comment on column public.notification_preferences.channel_whatsapp is
  'Future WhatsApp delivery. In-app remains the only live channel.';

-- Entity timeline lookups
create index if not exists company_activity_events_reference_idx
  on public.company_activity_events (company_id, reference_type, reference_id, created_at desc)
  where reference_id is not null;

create index if not exists notifications_reference_idx
  on public.notifications (company_id, reference_type, reference_id)
  where deleted_at is null and reference_id is not null;

-- Ensure prefs rows exist for all categories (idempotent seed helper)
create or replace function public.ensure_notification_preferences(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  company uuid;
  cat text;
begin
  select e.company_id into company
  from public.employees e
  where e.id = p_employee_id
    and e.deleted_at is null;

  if company is null then
    return;
  end if;

  foreach cat in array array[
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
      company,
      p_employee_id,
      cat,
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

revoke all on function public.ensure_notification_preferences(uuid) from public;
grant execute on function public.ensure_notification_preferences(uuid) to authenticated;
