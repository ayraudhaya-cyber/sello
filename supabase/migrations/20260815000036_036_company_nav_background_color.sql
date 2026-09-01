-- =============================================================================
-- 036 — Optional dark chrome colour for sidebar + branded launch
--
-- Entitled tenants may set nav_background_color (hex). Empty/null keeps the
-- Sello Hub rail. Writes follow the existing branding trigger (owner/admin
-- when custom_branding_enabled). Does not recolour page canvas or surfaces.
-- =============================================================================

alter table public.company_settings
  add column if not exists nav_background_color text;

alter table public.company_settings
  drop constraint if exists company_settings_nav_background_color_format;

alter table public.company_settings
  add constraint company_settings_nav_background_color_format
  check (
    nav_background_color is null
    or nav_background_color ~ '^#[0-9A-Fa-f]{6}$'
  );

comment on column public.company_settings.nav_background_color is
  'Optional dark chrome for Hub sidebar and branded splash/login. Null uses Sello rail.';

create or replace function public.protect_company_branding()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    NEW.custom_branding_enabled := false;
    return NEW;
  end if;

  if NEW.custom_branding_enabled is distinct from OLD.custom_branding_enabled then
    raise exception 'custom_branding_enabled cannot be changed from the application'
      using errcode = '42501';
  end if;

  if NEW.logo_url is distinct from OLD.logo_url
     or NEW.primary_color is distinct from OLD.primary_color
     or NEW.nav_background_color is distinct from OLD.nav_background_color then
    if not public.can_manage_company_branding() then
      raise exception 'You do not have permission to update business branding'
        using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$$;
