-- =============================================================================
-- Migration 004 — Server-side pending business onboarding
--
-- Replaces client-local pending provision storage with a durable, cross-device
-- pending row keyed to auth.users.
--
-- Lifecycle:
--   1. Client signs up with raw_user_meta_data.pending_business (no password).
--   2. Trigger copies metadata → pending_business_provisions.
--   3. After email verify + authenticated session:
--        complete_business_onboarding() creates the tenant exactly once.
--   4. Authenticated users without a pending row can upsert via
--        upsert_pending_business_provision() (recovery / re-entry).
--
-- Auth remains the identity source. Provisioning remains a separate step that
-- always runs under auth.uid().
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Pending onboarding rows
-- -----------------------------------------------------------------------------

create table public.pending_business_provisions (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  business_name text not null,
  company_code text not null,
  owner_full_name text not null,
  owner_email text not null,
  owner_phone text,
  branch_name text not null,
  branch_code text not null,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'cancelled')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null
    default (timezone('utc', now()) + interval '14 days'),

  constraint pending_business_name_not_blank
    check (length(trim(business_name)) > 0),
  constraint pending_company_code_format
    check (company_code ~ '^[A-Z0-9][A-Z0-9_-]*$'),
  constraint pending_owner_name_not_blank
    check (length(trim(owner_full_name)) > 0),
  constraint pending_owner_email_not_blank
    check (length(trim(owner_email)) > 0),
  constraint pending_branch_name_not_blank
    check (length(trim(branch_name)) > 0),
  constraint pending_branch_code_format
    check (branch_code ~ '^[A-Z0-9][A-Z0-9_-]*$')
);

create unique index pending_business_provisions_company_code_pending_key
  on public.pending_business_provisions (company_code)
  where status = 'pending';

create index pending_business_provisions_status_idx
  on public.pending_business_provisions (status);

create index pending_business_provisions_expires_at_idx
  on public.pending_business_provisions (expires_at)
  where status = 'pending';

create trigger trg_pending_business_provisions_set_updated_at
before update on public.pending_business_provisions
for each row execute function public.set_updated_at();

alter table public.pending_business_provisions enable row level security;

-- Clients may read their own pending row (debugging / future status UI).
-- All writes go through SECURITY DEFINER RPCs / the auth trigger.
create policy pending_business_provisions_select_own
  on public.pending_business_provisions
  for select
  to authenticated
  using (auth_user_id = auth.uid());

revoke all on table public.pending_business_provisions from public;
grant select on table public.pending_business_provisions to authenticated;

-- -----------------------------------------------------------------------------
-- Availability: company code (active companies + pending reservations)
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

  if exists (
    select 1
    from public.companies c
    where c.company_code = v_code
      and c.deleted_at is null
  ) then
    return false;
  end if;

  if exists (
    select 1
    from public.pending_business_provisions p
    where p.company_code = v_code
      and p.status = 'pending'
      and p.expires_at > timezone('utc', now())
  ) then
    return false;
  end if;

  return true;
end;
$$;

-- -----------------------------------------------------------------------------
-- Shared tenant bootstrap (internal — not granted to clients)
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

  -- TODO: currency / timezone / locale from onboarding in a future milestone.
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

-- -----------------------------------------------------------------------------
-- Rewrite provision_business → thin authenticated wrapper
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
begin
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED'
      using errcode = 'P0001',
            hint = 'Sign up before provisioning a business.';
  end if;

  return public.provision_tenant_for_auth_user(
    v_user_id,
    p_business_name,
    p_company_code,
    p_owner_full_name,
    p_owner_email,
    p_owner_phone,
    p_branch_name,
    p_branch_code
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Upsert pending row for the authenticated caller (recovery / re-entry)
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
    from public.pending_business_provisions p
    where p.company_code = v_company_code
      and p.status = 'pending'
      and p.expires_at > timezone('utc', now())
      and p.auth_user_id <> v_user_id
  ) then
    raise exception 'COMPANY_CODE_TAKEN' using errcode = 'P0001';
  end if;

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
  set
    business_name = excluded.business_name,
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

revoke all on function public.upsert_pending_business_provision(
  text, text, text, text, text, text
) from public;
grant execute on function public.upsert_pending_business_provision(
  text, text, text, text, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- Complete onboarding for the authenticated caller (idempotent)
-- -----------------------------------------------------------------------------

create or replace function public.complete_business_onboarding()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_pending public.pending_business_provisions%rowtype;
  v_result jsonb;
  v_company_id uuid;
  v_branch_id uuid;
  v_employee_id uuid;
  v_role_id uuid;
  v_company_code text;
  v_slug text;
begin
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;

  -- Already provisioned → return existing tenant snapshot (safe retry).
  select
    e.company_id,
    e.branch_id,
    e.id,
    e.role_id,
    c.company_code,
    c.slug
  into
    v_company_id,
    v_branch_id,
    v_employee_id,
    v_role_id,
    v_company_code,
    v_slug
  from public.employees e
  join public.companies c on c.id = e.company_id
  where e.user_id = v_user_id
    and e.deleted_at is null
  limit 1;

  if v_employee_id is not null then
    update public.pending_business_provisions
    set status = 'completed',
        updated_at = timezone('utc', now())
    where auth_user_id = v_user_id
      and status = 'pending';

    return jsonb_build_object(
      'company_id', v_company_id,
      'branch_id', v_branch_id,
      'employee_id', v_employee_id,
      'role_id', v_role_id,
      'company_code', v_company_code,
      'slug', v_slug,
      'already_provisioned', true
    );
  end if;

  select * into v_pending
  from public.pending_business_provisions p
  where p.auth_user_id = v_user_id
    and p.status = 'pending';

  if not found then
    raise exception 'NO_PENDING_ONBOARDING'
      using errcode = 'P0001',
            hint = 'No business details are waiting for this account.';
  end if;

  if v_pending.expires_at <= timezone('utc', now()) then
    update public.pending_business_provisions
    set status = 'cancelled',
        updated_at = timezone('utc', now())
    where auth_user_id = v_user_id;

    raise exception 'PENDING_EXPIRED'
      using errcode = 'P0001',
            hint = 'Your business setup expired. Please start onboarding again.';
  end if;

  v_result := public.provision_tenant_for_auth_user(
    v_user_id,
    v_pending.business_name,
    v_pending.company_code,
    v_pending.owner_full_name,
    v_pending.owner_email,
    v_pending.owner_phone,
    v_pending.branch_name,
    v_pending.branch_code
  );

  update public.pending_business_provisions
  set status = 'completed',
      updated_at = timezone('utc', now())
  where auth_user_id = v_user_id;

  return v_result || jsonb_build_object('already_provisioned', false);
end;
$$;

revoke all on function public.complete_business_onboarding() from public;
grant execute on function public.complete_business_onboarding() to authenticated;

-- -----------------------------------------------------------------------------
-- Auth signup → pending row (cross-device source of truth)
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
    from public.pending_business_provisions p
    where p.company_code = v_company_code
      and p.status = 'pending'
      and p.expires_at > timezone('utc', now())
  ) then
    raise exception 'COMPANY_CODE_TAKEN' using errcode = 'P0001';
  end if;

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

drop trigger if exists on_auth_user_created_pending_business on auth.users;
create trigger on_auth_user_created_pending_business
  after insert on auth.users
  for each row
  execute function public.handle_new_auth_user_pending_business();

-- -----------------------------------------------------------------------------
-- Rollback: also cancel any pending row for the caller
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

  if exists (
    select 1
    from public.employees e
    where e.user_id = v_user_id
  ) then
    raise exception 'CANNOT_ROLLBACK_PROVISIONED'
      using errcode = 'P0001';
  end if;

  update public.pending_business_provisions
  set status = 'cancelled',
      updated_at = timezone('utc', now())
  where auth_user_id = v_user_id
    and status = 'pending';

  delete from auth.users where id = v_user_id;
end;
$$;

-- =============================================================================
-- Notes
-- - Passwords are never stored in pending rows or user metadata.
-- - complete_business_onboarding is the only post-auth provisioning entrypoint
--   the app should call; it is idempotent and scoped to auth.uid().
-- - Company codes are reserved while status = pending and unexpired.
-- =============================================================================
