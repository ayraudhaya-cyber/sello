-- =============================================================================
-- 034 — Company custom branding entitlement + storage
--
-- Adds tenant flag custom_branding_enabled (default false). Clients cannot
-- flip this from the app — only service-role / migrations / Sello admin SQL.
--
-- Logo + primary colour remain on company_settings. Writes are restricted to
-- owner / administrator when the entitlement is on. Matches app IAM:
-- RolePermissionProfile manageSettings is true only for those roles.
-- =============================================================================

alter table public.company_settings
  add column if not exists custom_branding_enabled boolean not null default false;

comment on column public.company_settings.custom_branding_enabled is
  'Sello entitlement for custom branding settings. Not editable by client users.';

-- Initial entitled client (demo / requested tenant).
update public.company_settings cs
set custom_branding_enabled = true
from public.companies c
where c.id = cs.company_id
  and c.company_code = 'UNITECH'
  and c.deleted_at is null;

grant execute on function public.current_role_code() to authenticated;

-- True when the signed-in employee may change logo / primary colour.
create or replace function public.can_manage_company_branding()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := public.current_role_code();
  v_company uuid := public.current_company_id();
  v_enabled boolean;
begin
  if v_role is null or v_company is null then
    return false;
  end if;

  -- Mirrors RolePermissionProfile manageSettings (owner + administrator).
  -- Manager is settings view-only; Sales has no settings write access.
  if v_role not in ('owner', 'administrator') then
    return false;
  end if;

  select cs.custom_branding_enabled
  into v_enabled
  from public.company_settings cs
  where cs.company_id = v_company;

  return coalesce(v_enabled, false);
end;
$$;

comment on function public.can_manage_company_branding() is
  'Owner/administrator may edit logo and primary colour only when custom_branding_enabled is true.';

revoke all on function public.can_manage_company_branding() from public;
grant execute on function public.can_manage_company_branding() to authenticated;

create or replace function public.protect_company_branding()
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
    -- Client users cannot self-entitle a new settings row.
    NEW.custom_branding_enabled := false;
    return NEW;
  end if;

  if NEW.custom_branding_enabled is distinct from OLD.custom_branding_enabled then
    raise exception 'custom_branding_enabled cannot be changed from the application'
      using errcode = '42501';
  end if;

  if NEW.logo_url is distinct from OLD.logo_url
     or NEW.primary_color is distinct from OLD.primary_color then
    if not public.can_manage_company_branding() then
      raise exception 'You do not have permission to update business branding'
        using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_company_settings_protect_branding
  on public.company_settings;
create trigger trg_company_settings_protect_branding
before insert or update on public.company_settings
for each row execute function public.protect_company_branding();

-- ---------------------------------------------------------------------------
-- Storage — public logos (splash / login need HTTPS without a session)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'company-branding',
  'company-branding',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "company_branding_public_read" on storage.objects;
create policy "company_branding_public_read"
  on storage.objects
  for select
  to public
  using (bucket_id = 'company-branding');

drop policy if exists "company_branding_insert_managers" on storage.objects;
create policy "company_branding_insert_managers"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.can_manage_company_branding()
  );

drop policy if exists "company_branding_update_managers" on storage.objects;
create policy "company_branding_update_managers"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.can_manage_company_branding()
  )
  with check (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.can_manage_company_branding()
  );

drop policy if exists "company_branding_delete_managers" on storage.objects;
create policy "company_branding_delete_managers"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.can_manage_company_branding()
  );
