-- =============================================================================
-- 058 — Employee login invite authorization (server-side Auth creation)
--
-- Client browsers must not call auth.signUp() for team invites (BroadcastChannel
-- signs the Owner out on web). Auth user creation moves to the
-- `invite-employee-login` Edge Function (service role).
--
-- This migration only adds the JWT-scoped gate the Edge Function calls before
-- privileged Auth Admin work. No schema changes to employees / employee_invites.
-- =============================================================================

create or replace function public.prepare_employee_login_invite(
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := public.current_employee_id();
  v_company_id uuid := public.current_company_id();
  v_actor_role text;
  v_email text;
  v_full_name text;
  v_user_id uuid;
  v_status text;
  v_active boolean;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'unauthorized');
  end if;

  if v_actor_id is null or v_company_id is null then
    return jsonb_build_object('ok', false, 'reason', 'unauthorized');
  end if;

  if p_employee_id is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid_request');
  end if;

  select lower(r.code)
  into v_actor_role
  from public.employees e
  join public.roles r on r.id = e.role_id
  where e.id = v_actor_id
    and e.company_id = v_company_id
    and e.deleted_at is null
    and e.is_active = true;

  if v_actor_role is null then
    return jsonb_build_object('ok', false, 'reason', 'unauthorized');
  end if;

  -- Match Hub IAM: Owner / Manager (and Administrator) may invite.
  if v_actor_role not in ('owner', 'manager', 'administrator') then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;

  select
    lower(trim(e.email)),
    e.full_name,
    e.user_id,
    e.employment_status,
    e.is_active
  into
    v_email,
    v_full_name,
    v_user_id,
    v_status,
    v_active
  from public.employees e
  where e.id = p_employee_id
    and e.company_id = v_company_id
    and e.deleted_at is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v_active is not true or v_status is distinct from 'active' then
    return jsonb_build_object('ok', false, 'reason', 'inactive');
  end if;

  if v_email is null or v_email = '' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_email');
  end if;

  return jsonb_build_object(
    'ok', true,
    'employee_id', p_employee_id,
    'company_id', v_company_id,
    'actor_employee_id', v_actor_id,
    'email', v_email,
    'full_name', v_full_name,
    'auth_user_id', v_user_id
  );
end;
$$;

comment on function public.prepare_employee_login_invite(uuid) is
  'JWT-scoped gate for invite-employee-login. Returns target employee email '
  'and company from auth.uid() — never trusts a client-supplied company_id.';

revoke all on function public.prepare_employee_login_invite(uuid) from public;
grant execute on function public.prepare_employee_login_invite(uuid)
  to authenticated;

-- Service-role link after Auth Admin createUser (idempotent).
create or replace function public.link_employee_auth_user(
  p_company_id uuid,
  p_employee_id uuid,
  p_auth_user_id uuid,
  p_actor_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing uuid;
  v_other uuid;
begin
  if p_company_id is null
    or p_employee_id is null
    or p_auth_user_id is null
    or p_actor_employee_id is null
  then
    return jsonb_build_object('ok', false, 'reason', 'invalid_request');
  end if;

  -- Actor must belong to the same company (defense in depth for service role).
  if not exists (
    select 1
    from public.employees a
    where a.id = p_actor_employee_id
      and a.company_id = p_company_id
      and a.deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;

  select e.user_id
  into v_existing
  from public.employees e
  where e.id = p_employee_id
    and e.company_id = p_company_id
    and e.deleted_at is null
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v_existing is not null then
    if v_existing = p_auth_user_id then
      return jsonb_build_object(
        'ok', true,
        'already_linked', true,
        'auth_user_id', v_existing
      );
    end if;
    return jsonb_build_object('ok', false, 'reason', 'already_linked_other');
  end if;

  select e.id
  into v_other
  from public.employees e
  where e.user_id = p_auth_user_id
    and e.deleted_at is null
  limit 1;

  if v_other is not null then
    return jsonb_build_object('ok', false, 'reason', 'auth_user_in_use');
  end if;

  update public.employees
  set user_id = p_auth_user_id,
      updated_by = p_actor_employee_id,
      updated_at = timezone('utc', now())
  where id = p_employee_id
    and company_id = p_company_id
    and deleted_at is null
    and user_id is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'link_failed');
  end if;

  return jsonb_build_object(
    'ok', true,
    'already_linked', false,
    'auth_user_id', p_auth_user_id
  );
end;
$$;

comment on function public.link_employee_auth_user(uuid, uuid, uuid, uuid) is
  'Service-role only. Links employees.user_id after Auth Admin user create.';

revoke all on function public.link_employee_auth_user(uuid, uuid, uuid, uuid)
  from public;
revoke all on function public.link_employee_auth_user(uuid, uuid, uuid, uuid)
  from anon;
revoke all on function public.link_employee_auth_user(uuid, uuid, uuid, uuid)
  from authenticated;
grant execute on function public.link_employee_auth_user(uuid, uuid, uuid, uuid)
  to service_role;
