-- =============================================================================
-- 050 — Sender ID is server-managed; tenants cannot edit unless Sello enables it
--
-- The Text.lk sender_id used by send-outbound-sms always comes from
-- company_settings.sms_sender_id (claim RPCs). Clients cannot supply it.
-- sms_sender_id_editable defaults false. Only SQL / service role can flip it.
-- =============================================================================

alter table public.company_settings
  add column if not exists sms_sender_id_editable boolean not null default false;

comment on column public.company_settings.sms_sender_id_editable is
  'Sello entitlement. When false (default), tenants cannot change sms_sender_id. Not editable from the app.';

comment on column public.company_settings.sms_sender_id is
  'Approved Text.lk Sender ID for this tenant. Used by every SMS (orders, collections, Test SMS). API token is never stored here.';

create or replace function public.can_edit_sms_sender_id()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.current_role_code(), '') in (
      'owner',
      'manager',
      'administrator'
    )
    and exists (
      select 1
      from public.company_settings cs
      where cs.company_id = public.current_company_id()
        and cs.sms_sender_id_editable
    );
$$;

comment on function public.can_edit_sms_sender_id() is
  'Owner/Manager/Administrator may change sms_sender_id only when sms_sender_id_editable is true.';

grant execute on function public.can_edit_sms_sender_id() to authenticated;

create or replace function public.company_settings_guard_sms_sender_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- No JWT (service role / dashboard SQL / migrations) may change anything.
  if auth.uid() is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    NEW.sms_sender_id_editable := false;
    NEW.sms_sender_id := null;
    return NEW;
  end if;

  if NEW.sms_sender_id_editable is distinct from OLD.sms_sender_id_editable then
    raise exception 'sms_sender_id_editable cannot be changed from the application'
      using errcode = '42501';
  end if;

  if NEW.sms_sender_id is distinct from OLD.sms_sender_id then
    if not coalesce(OLD.sms_sender_id_editable, false) then
      raise exception 'SMS Sender ID is managed by Sello.'
        using errcode = '42501';
    end if;
    if not public.can_edit_sms_sender_id() then
      raise exception 'Only an Owner or Manager can change the SMS Sender ID.'
        using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists company_settings_guard_sms_sender_id
  on public.company_settings;

create trigger company_settings_guard_sms_sender_id
  before insert or update on public.company_settings
  for each row
  execute function public.company_settings_guard_sms_sender_id();
