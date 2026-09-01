-- =============================================================================
-- Migration 003 — Business Provisioning
--
-- Enables self-serve tenant onboarding without service-role / Dashboard work.
--
-- Exposes:
--   is_company_code_available(text)  — anon + authenticated (wizard step 1)
--   is_owner_email_available(text)   — anon + authenticated (wizard step 2)
--   provision_business(...)          — authenticated; creates company + HO +
--                                      owner employee linked to auth.uid()
--   rollback_failed_provisioning()   — authenticated; deletes auth user only
--                                      when no employee row exists (cleanup)
--
-- All DB writes for a new business run inside one Postgres function so they
-- commit or roll back together. Auth user create/delete stays outside that
-- transaction and is coordinated by the Flutter provisioning coordinator.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Availability: company code
-- -----------------------------------------------------------------------------

create or replace function public.is_company_code_available(p_company_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_company_code, '')));
begin
  if v_code = '' then
    return false;
  end if;

  return not exists (
    select 1
    from public.companies c
    where c.company_code = v_code
      and c.deleted_at is null
  );
end;
$$;

revoke all on function public.is_company_code_available(text) from public;
grant execute on function public.is_company_code_available(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Availability: owner email (auth.users + employees)
-- -----------------------------------------------------------------------------

create or replace function public.is_owner_email_available(p_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if v_email = '' then
    return false;
  end if;

  if exists (
    select 1
    from auth.users u
    where lower(u.email) = v_email
  ) then
    return false;
  end if;

  if exists (
    select 1
    from public.employees e
    where lower(e.email) = v_email
      and e.deleted_at is null
  ) then
    return false;
  end if;

  return true;
end;
$$;

revoke all on function public.is_owner_email_available(text) from public;
grant execute on function public.is_owner_email_available(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Provision business (transactional tenancy bootstrap)
-- -----------------------------------------------------------------------------

create or replace function public.provision_business(
  p_business_name text,
  p_company_code text,
  p_owner_full_name text,
  p_owner_email text,
  p_owner_phone text default null,
  p_branch_name text default 'Head Office',
  p_branch_code text default 'HO'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_name text := trim(coalesce(p_business_name, ''));
  v_company_code text := upper(trim(coalesce(p_company_code, '')));
  v_owner_name text := trim(coalesce(p_owner_full_name, ''));
  v_owner_email text := lower(trim(coalesce(p_owner_email, '')));
  v_owner_phone text := nullif(trim(coalesce(p_owner_phone, '')), '');
  v_branch_name text := trim(coalesce(p_branch_name, ''));
  v_branch_code text := upper(trim(coalesce(p_branch_code, '')));
  v_slug text;
  v_role_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_employee_id uuid;
  v_auth_email text;
begin
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED'
      using errcode = 'P0001',
            hint = 'Sign up before provisioning a business.';
  end if;

  -- Reject callers who already belong to a company.
  if exists (
    select 1
    from public.employees e
    where e.user_id = v_user_id
      and e.deleted_at is null
  ) then
    raise exception 'ALREADY_PROVISIONED'
      using errcode = 'P0001',
            hint = 'This account already belongs to a business.';
  end if;

  select lower(u.email) into v_auth_email
  from auth.users u
  where u.id = v_user_id;

  if v_auth_email is null then
    raise exception 'AUTH_USER_MISSING'
      using errcode = 'P0001';
  end if;

  if v_owner_email <> v_auth_email then
    raise exception 'EMAIL_MISMATCH'
      using errcode = 'P0001',
            hint = 'Owner email must match the signed-in account.';
  end if;

  if v_business_name = '' then
    raise exception 'INVALID_BUSINESS_NAME' using errcode = 'P0001';
  end if;

  if v_company_code = '' or v_company_code !~ '^[A-Z0-9][A-Z0-9_-]*$' then
    raise exception 'INVALID_COMPANY_CODE' using errcode = 'P0001';
  end if;

  if v_owner_name = '' then
    raise exception 'INVALID_OWNER_NAME' using errcode = 'P0001';
  end if;

  if v_branch_name = '' then
    raise exception 'INVALID_BRANCH_NAME' using errcode = 'P0001';
  end if;

  if v_branch_code = '' or v_branch_code !~ '^[A-Z0-9][A-Z0-9_-]*$' then
    raise exception 'INVALID_BRANCH_CODE' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.companies c
    where c.company_code = v_company_code
      and c.deleted_at is null
  ) then
    raise exception 'COMPANY_CODE_TAKEN' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employees e
    where lower(e.email) = v_owner_email
      and e.deleted_at is null
  ) then
    raise exception 'EMAIL_TAKEN' using errcode = 'P0001';
  end if;

  select r.id into strict v_role_id
  from public.roles r
  where r.code = 'owner';

  -- Slug from business name (user-facing); company_code remains the internal id.
  -- Example: "Unitech Solutions" → "unitech-solutions"
  v_slug := lower(trim(v_business_name));
  v_slug := regexp_replace(v_slug, '[^a-z0-9]+', '-', 'g');
  v_slug := regexp_replace(v_slug, '-+', '-', 'g');
  v_slug := trim(both '-' from v_slug);

  -- Fallback to company code if the business name yields no usable slug.
  if v_slug = '' or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    v_slug := lower(regexp_replace(v_company_code, '_+', '-', 'g'));
    v_slug := regexp_replace(v_slug, '-+', '-', 'g');
    v_slug := trim(both '-' from v_slug);
  end if;

  if v_slug = '' or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'INVALID_BUSINESS_NAME' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.companies c
    where c.slug = v_slug and c.deleted_at is null
  ) then
    v_slug := v_slug || '-' || substr(replace(v_user_id::text, '-', ''), 1, 8);
  end if;

  -- =====================================================
  -- Transaction begins here.
  -- Any exception will roll back all company data.
  -- (Entire function body runs in one Postgres transaction.)
  -- =====================================================

  insert into public.companies (
    name,
    legal_name,
    company_code,
    slug,
    is_active
  )
  values (
    v_business_name,
    v_business_name,
    v_company_code,
    v_slug,
    true
  )
  returning id into v_company_id;

  -- TODO:
  -- Currency, timezone and locale will be selected during onboarding
  -- in a future milestone. These defaults are temporary.
  insert into public.company_settings (
    company_id,
    primary_color,
    secondary_color,
    currency,
    timezone,
    locale
  )
  values (
    v_company_id,
    '#9619F1',
    '#4237E7',
    'USD',
    'UTC',
    'en-US'
  );

  insert into public.branches (
    company_id,
    name,
    code,
    is_active
  )
  values (
    v_company_id,
    v_branch_name,
    v_branch_code,
    true
  )
  returning id into v_branch_id;

  insert into public.employees (
    company_id,
    branch_id,
    role_id,
    user_id,
    email,
    full_name,
    phone,
    is_active
  )
  values (
    v_company_id,
    v_branch_id,
    v_role_id,
    v_user_id,
    v_owner_email,
    v_owner_name,
    v_owner_phone,
    true
  )
  returning id into v_employee_id;

  -- Stamp audit columns now that the owner employee exists.
  update public.companies
  set created_by = v_employee_id,
      updated_by = v_employee_id
  where id = v_company_id;

  update public.company_settings
  set created_by = v_employee_id,
      updated_by = v_employee_id
  where company_id = v_company_id;

  update public.branches
  set created_by = v_employee_id,
      updated_by = v_employee_id
  where id = v_branch_id;

  update public.employees
  set created_by = v_employee_id,
      updated_by = v_employee_id
  where id = v_employee_id;

  return jsonb_build_object(
    'company_id', v_company_id,
    'branch_id', v_branch_id,
    'employee_id', v_employee_id,
    'role_id', v_role_id,
    'company_code', v_company_code,
    'slug', v_slug
  );
end;
$$;

revoke all on function public.provision_business(
  text, text, text, text, text, text, text
) from public;
grant execute on function public.provision_business(
  text, text, text, text, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- Rollback orphaned auth user after a failed provision attempt
-- -----------------------------------------------------------------------------

create or replace function public.rollback_failed_provisioning()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    return;
  end if;

  -- Never delete an account that already has an employee profile.
  if exists (
    select 1
    from public.employees e
    where e.user_id = v_user_id
  ) then
    raise exception 'CANNOT_ROLLBACK_PROVISIONED'
      using errcode = 'P0001';
  end if;

  -- Soft-delete any orphaned company rows should not exist (RPC is atomic),
  -- but remove the auth user so the email can be reused.
  delete from auth.users where id = v_user_id;
end;
$$;

revoke all on function public.rollback_failed_provisioning() from public;
grant execute on function public.rollback_failed_provisioning() to authenticated;

-- =============================================================================
-- Future Enhancements
-- - Country selection
-- - Default currency from country
-- - Default timezone from country
-- - Default locale from country
-- - Trial subscription creation
-- - Welcome email
-- - Audit event
-- =============================================================================
