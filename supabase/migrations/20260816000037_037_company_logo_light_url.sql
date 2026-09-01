-- =============================================================================
-- 037 — Light-surface logo for entitled custom branding
--
-- logo_url remains the reverse/light wordmark for dark chrome (sidebar,
-- splash, branded app bars). logo_light_url is the dark-ink wordmark for
-- light canvases such as Sales Home. Null uses the Sello mark.
-- =============================================================================

alter table public.company_settings
  add column if not exists logo_light_url text;

comment on column public.company_settings.logo_light_url is
  'Optional dark-ink wordmark for light surfaces (Sales Home). Null uses Sello.';

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
     or NEW.logo_light_url is distinct from OLD.logo_light_url
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
