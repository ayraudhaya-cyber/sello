-- =============================================================================
-- Migration 045 — Temporary invite-only gate for NEW self-service tenants
--
-- Check order:
--   1. Client calls sello_signup_is_allowed (boolean only) before Auth signup.
--   2. BEFORE INSERT on auth.users rejects pending_business signups that are
--      not invited (rolls back the auth user in the same statement).
--   3. provision_tenant_for_auth_user asserts again so no company/Owner/HO
--      can be created without an approved invite.
-- Employee-invite Auth users (no pending_business) and existing employees
-- skip this gate. Login never reads sello_tenant_invites.
--
-- Activation seam (do not add Stripe here):
--   sello_signup_is_allowed(email) is the single check.
--   Later, replace its body with an active-subscription test without changing
--   Auth signup or complete_business_onboarding.
--
-- Manual management (SQL Editor / service role). Clients cannot write rows.
-- =============================================================================

create table public.sello_tenant_invites (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  status text not null default 'approved'
    check (status in ('approved', 'used', 'revoked')),
  company_name text,
  created_at timestamptz not null default timezone('utc', now()),
  approved_at timestamptz not null default timezone('utc', now()),
  used_at timestamptz,
  expires_at timestamptz,

  constraint sello_tenant_invites_email_not_blank
    check (length(trim(email)) > 0)
);

create unique index sello_tenant_invites_email_key
  on public.sello_tenant_invites (email);

create index sello_tenant_invites_status_idx
  on public.sello_tenant_invites (status);

create or replace function public.sello_tenant_invites_normalize()
returns trigger
language plpgsql
as $$
begin
  new.email := lower(trim(new.email));
  if new.email = '' then
    raise exception 'INVALID_INVITE_EMAIL' using errcode = 'P0001';
  end if;
  if new.status = 'approved' and new.approved_at is null then
    new.approved_at := timezone('utc', now());
  end if;
  return new;
end;
$$;

create trigger trg_sello_tenant_invites_normalize
before insert or update on public.sello_tenant_invites
for each row execute function public.sello_tenant_invites_normalize();

alter table public.sello_tenant_invites enable row level security;

revoke all on table public.sello_tenant_invites from public;
revoke all on table public.sello_tenant_invites from anon;
revoke all on table public.sello_tenant_invites from authenticated;

-- -----------------------------------------------------------------------------
-- Single activation check (invite today, subscription later)
-- -----------------------------------------------------------------------------

create or replace function public.sello_signup_is_allowed(p_email text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if v_email = '' then
    return false;
  end if;

  return exists (
    select 1
    from public.sello_tenant_invites i
    where i.email = v_email
      and i.status = 'approved'
      and (i.expires_at is null or i.expires_at > timezone('utc', now()))
  );
end;
$$;

create or replace function public.assert_sello_signup_allowed(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.sello_signup_is_allowed(p_email) then
    raise exception 'SIGNUP_NOT_INVITED' using errcode = 'P0001';
  end if;
end;
$$;

-- Boolean only — does not reveal invite rows or statuses.
revoke all on function public.sello_signup_is_allowed(text) from public;
grant execute on function public.sello_signup_is_allowed(text) to anon, authenticated;

revoke all on function public.assert_sello_signup_allowed(text) from public;
revoke all on function public.assert_sello_signup_allowed(text) from anon;
revoke all on function public.assert_sello_signup_allowed(text) from authenticated;

-- -----------------------------------------------------------------------------
-- Block uninvited Auth signup (pending_business only). Employee invites skip.
-- BEFORE INSERT so a failed check rolls back auth.users in the same statement.
-- -----------------------------------------------------------------------------

create or replace function public.assert_pending_business_invite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  v_payload := new.raw_user_meta_data -> 'pending_business';
  if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
    return new;
  end if;

  perform public.assert_sello_signup_allowed(new.email);
  return new;
end;
$$;

drop trigger if exists trg_auth_users_require_signup_invite on auth.users;
create trigger trg_auth_users_require_signup_invite
  before insert on auth.users
  for each row
  execute function public.assert_pending_business_invite();

revoke all on function public.assert_pending_business_invite() from public;

-- -----------------------------------------------------------------------------
-- Recovery upsert must not stash pending onboarding for uninvited emails
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

  perform public.assert_sello_signup_allowed(v_owner_email);

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
-- Hard gate: no company / Owner / Head Office without an approved invite
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

  perform public.assert_sello_signup_allowed(v_owner_email);

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

  update public.sello_tenant_invites
  set status = 'used',
      used_at = timezone('utc', now())
  where email = v_owner_email
    and status = 'approved';

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

-- =============================================================================
-- Manual invite management (run in SQL Editor as postgres / service role)
--
-- Approve:
--   insert into public.sello_tenant_invites (email, company_name)
--   values ('owner@acme.com', 'Acme');
--
-- Revoke:
--   update public.sello_tenant_invites
--   set status = 'revoked'
--   where email = lower(trim('owner@acme.com'));
--
-- View:
--   select email, status, company_name, approved_at, used_at, expires_at
--   from public.sello_tenant_invites
--   order by created_at desc;
-- =============================================================================
