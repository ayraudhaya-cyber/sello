-- =============================================================================
-- Migration 044 — Self-service signup company-code collisions
--
-- Public signup no longer asks the user for a company code. Codes are derived
-- from the business name. Two "Acme" signups must not fail or join each other.
--
-- next_unique_company_code is internal (not granted to clients). Tenant
-- creation still happens only via complete_business_onboarding /
-- provision_tenant_for_auth_user under auth.uid() — never from a client
-- company_id.
--
-- Future Stripe: keep this activation path. Billing should run after email
-- verification and before complete_business_onboarding, without a second
-- tenant-create RPC.
-- =============================================================================

create or replace function public.next_unique_company_code(
  p_base text,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text := upper(regexp_replace(trim(coalesce(p_base, '')), '[^A-Z0-9_-]', '', 'g'));
  v_code text;
  v_n int := 0;
  v_suffix text;
begin
  if v_base = '' or v_base !~ '^[A-Z0-9][A-Z0-9_-]*$' then
    v_base := 'BIZ';
  end if;
  if length(v_base) > 32 then
    v_base := left(v_base, 32);
  end if;

  loop
    if v_n = 0 then
      v_code := v_base;
    elsif v_n < 40 then
      v_suffix := (v_n + 1)::text;
      v_code := left(v_base, 32 - length(v_suffix)) || v_suffix;
    else
      v_suffix := '-' || left(upper(replace(coalesce(p_user_id::text, gen_random_uuid()::text), '-', '')), 8);
      v_code := left(v_base, 32 - length(v_suffix)) || v_suffix;
    end if;

    if not exists (
      select 1
      from public.companies c
      where c.company_code = v_code
        and c.deleted_at is null
    ) and not exists (
      select 1
      from public.pending_business_provisions p
      where p.company_code = v_code
        and p.status = 'pending'
        and p.expires_at > timezone('utc', now())
        and p.auth_user_id is distinct from p_user_id
    ) then
      return v_code;
    end if;

    v_n := v_n + 1;
    if v_n > 40 then
      return v_code;
    end if;
  end loop;
end;
$$;

revoke all on function public.next_unique_company_code(text, uuid) from public;

-- -----------------------------------------------------------------------------
-- Trigger: copy signup metadata → pending row (collision-safe code)
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user_pending_business()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
  v_business_name text;
  v_company_code text;
  v_owner_name text;
  v_owner_phone text;
  v_branch_name text;
  v_branch_code text;
  v_owner_email text := lower(trim(coalesce(new.email, '')));
begin
  v_payload := new.raw_user_meta_data -> 'pending_business';
  if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
    return new;
  end if;

  if v_owner_email = '' then
    raise exception 'INVALID_OWNER_EMAIL' using errcode = 'P0001';
  end if;

  v_business_name := trim(coalesce(v_payload ->> 'business_name', ''));
  v_company_code := upper(trim(coalesce(v_payload ->> 'company_code', '')));
  v_owner_name := trim(coalesce(v_payload ->> 'owner_full_name', ''));
  v_owner_phone := nullif(trim(coalesce(v_payload ->> 'owner_phone', '')), '');
  v_branch_name := trim(coalesce(v_payload ->> 'branch_name', 'Head Office'));
  v_branch_code := upper(trim(coalesce(v_payload ->> 'branch_code', 'HO')));

  if v_business_name = '' then
    raise exception 'INVALID_BUSINESS_NAME' using errcode = 'P0001';
  end if;

  if v_owner_name = '' then
    raise exception 'INVALID_OWNER_NAME' using errcode = 'P0001';
  end if;

  if v_branch_name = '' then
    v_branch_name := 'Head Office';
  end if;

  if v_branch_code = '' or v_branch_code !~ '^[A-Z0-9][A-Z0-9_-]*$' then
    v_branch_code := 'HO';
  end if;

  v_company_code := public.next_unique_company_code(v_company_code, new.id);

  insert into public.pending_business_provisions (
    auth_user_id,
    business_name,
    company_code,
    owner_full_name,
    owner_email,
    owner_phone,
    branch_name,
    branch_code,
    status,
    expires_at
  )
  values (
    new.id,
    v_business_name,
    v_company_code,
    v_owner_name,
    v_owner_email,
    v_owner_phone,
    v_branch_name,
    v_branch_code,
    'pending',
    timezone('utc', now()) + interval '14 days'
  );

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Recovery upsert — same collision-safe code
-- -----------------------------------------------------------------------------

create or replace function public.upsert_pending_business_provision(
  p_business_name text,
  p_company_code text,
  p_owner_full_name text,
  p_owner_phone text default null,
  p_branch_name text default 'Head Office',
  p_branch_code text default 'HO'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_name text := trim(coalesce(p_business_name, ''));
  v_company_code text := upper(trim(coalesce(p_company_code, '')));
  v_owner_name text := trim(coalesce(p_owner_full_name, ''));
  v_owner_phone text := nullif(trim(coalesce(p_owner_phone, '')), '');
  v_branch_name text := trim(coalesce(p_branch_name, ''));
  v_branch_code text := upper(trim(coalesce(p_branch_code, '')));
  v_owner_email text;
begin
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employees e
    where e.user_id = v_user_id
      and e.deleted_at is null
  ) then
    raise exception 'ALREADY_PROVISIONED' using errcode = 'P0001';
  end if;

  select lower(u.email) into v_owner_email
  from auth.users u
  where u.id = v_user_id;

  if v_owner_email is null then
    raise exception 'AUTH_USER_MISSING' using errcode = 'P0001';
  end if;

  if v_business_name = '' then
    raise exception 'INVALID_BUSINESS_NAME' using errcode = 'P0001';
  end if;

  if v_owner_name = '' then
    raise exception 'INVALID_OWNER_NAME' using errcode = 'P0001';
  end if;

  if v_branch_name = '' then
    v_branch_name := 'Head Office';
  end if;

  if v_branch_code = '' or v_branch_code !~ '^[A-Z0-9][A-Z0-9_-]*$' then
    v_branch_code := 'HO';
  end if;

  v_company_code := public.next_unique_company_code(v_company_code, v_user_id);

  insert into public.pending_business_provisions (
    auth_user_id,
    business_name,
    company_code,
    owner_full_name,
    owner_email,
    owner_phone,
    branch_name,
    branch_code,
    status,
    expires_at
  )
  values (
    v_user_id,
    v_business_name,
    v_company_code,
    v_owner_name,
    v_owner_email,
    v_owner_phone,
    v_branch_name,
    v_branch_code,
    'pending',
    timezone('utc', now()) + interval '14 days'
  )
  on conflict (auth_user_id) do update
  set business_name = excluded.business_name,
      company_code = excluded.company_code,
      owner_full_name = excluded.owner_full_name,
      owner_email = excluded.owner_email,
      owner_phone = excluded.owner_phone,
      branch_name = excluded.branch_name,
      branch_code = excluded.branch_code,
      status = 'pending',
      expires_at = timezone('utc', now()) + interval '14 days',
      updated_at = timezone('utc', now());
end;
$$;

-- -----------------------------------------------------------------------------
-- Tenant bootstrap — Owner only, collision-safe company code
-- -----------------------------------------------------------------------------

create or replace function public.provision_tenant_for_auth_user(
  p_user_id uuid,
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
  if p_user_id is null then
    raise exception 'NOT_AUTHENTICATED'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employees e
    where e.user_id = p_user_id
      and e.deleted_at is null
  ) then
    raise exception 'ALREADY_PROVISIONED'
      using errcode = 'P0001',
            hint = 'This account already belongs to a business.';
  end if;

  select lower(u.email) into v_auth_email
  from auth.users u
  where u.id = p_user_id;

  if v_auth_email is null then
    raise exception 'AUTH_USER_MISSING' using errcode = 'P0001';
  end if;

  if v_owner_email <> v_auth_email then
    raise exception 'EMAIL_MISMATCH'
      using errcode = 'P0001',
            hint = 'Owner email must match the signed-in account.';
  end if;

  if v_business_name = '' then
    raise exception 'INVALID_BUSINESS_NAME' using errcode = 'P0001';
  end if;

  if v_owner_name = '' then
    raise exception 'INVALID_OWNER_NAME' using errcode = 'P0001';
  end if;

  if v_branch_name = '' then
    v_branch_name := 'Head Office';
  end if;

  if v_branch_code = '' or v_branch_code !~ '^[A-Z0-9][A-Z0-9_-]*$' then
    v_branch_code := 'HO';
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

  v_company_code := public.next_unique_company_code(v_company_code, p_user_id);

  v_slug := lower(trim(v_business_name));
  v_slug := regexp_replace(v_slug, '[^a-z0-9]+', '-', 'g');
  v_slug := regexp_replace(v_slug, '-+', '-', 'g');
  v_slug := trim(both '-' from v_slug);

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
    v_slug := v_slug || '-' || substr(replace(p_user_id::text, '-', ''), 1, 8);
  end if;

  insert into public.companies (
    name, legal_name, company_code, slug, is_active
  )
  values (
    v_business_name, v_business_name, v_company_code, v_slug, true
  )
  returning id into v_company_id;

  insert into public.company_settings (
    company_id, primary_color, secondary_color, currency, timezone, locale
  )
  values (
    v_company_id, '#9619F1', '#4237E7', 'USD', 'UTC', 'en-US'
  );

  insert into public.branches (
    company_id, name, code, is_active
  )
  values (
    v_company_id, v_branch_name, v_branch_code, true
  )
  returning id into v_branch_id;

  insert into public.employees (
    company_id, branch_id, role_id, user_id, email, full_name, phone, is_active
  )
  values (
    v_company_id, v_branch_id, v_role_id, p_user_id,
    v_owner_email, v_owner_name, v_owner_phone, true
  )
  returning id into v_employee_id;

  update public.companies
  set created_by = v_employee_id, updated_by = v_employee_id
  where id = v_company_id;

  update public.company_settings
  set created_by = v_employee_id, updated_by = v_employee_id
  where company_id = v_company_id;

  update public.branches
  set created_by = v_employee_id, updated_by = v_employee_id
  where id = v_branch_id;

  update public.employees
  set created_by = v_employee_id, updated_by = v_employee_id
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

revoke all on function public.provision_tenant_for_auth_user(
  uuid, text, text, text, text, text, text, text
) from public;
