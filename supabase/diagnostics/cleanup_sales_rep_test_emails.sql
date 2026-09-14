-- =============================================================================
-- cleanup_sales_rep_test_emails.sql
-- NOT a migration. Paste into Supabase SQL Editor (postgres / service role).
--
-- Removes ONLY these Sales Rep test identities so invites can be retested:
--   velvetkutty@gmail.com
--   angelayra0313@gmail.com
--
-- Deletes: employee_invites, related visit/notification rows, employees,
--          and matching auth.users.
-- Does NOT delete companies.
--
-- No Unitech keep-guard (safe while there are no real tenants yet).
-- After success you do NOT need to delete Auth users in the Dashboard.
-- =============================================================================

begin;

do $$
declare
  v_emails text[] := array[
    'velvetkutty@gmail.com',
    'angelayra0313@gmail.com'
  ];
  v_email text;
  v_norm text;
  v_emp_ids uuid[];
  v_auth_ids uuid[];
  v_n integer;
begin
  foreach v_email in array v_emails
  loop
    v_norm := lower(trim(v_email));
    raise notice '--- Cleaning % ---', v_norm;

    select coalesce(array_agg(e.id), array[]::uuid[])
    into v_emp_ids
    from public.employees e
    where lower(trim(e.email)) = v_norm;

    select coalesce(array_agg(u.id), array[]::uuid[])
    into v_auth_ids
    from auth.users u
    where lower(u.email) = v_norm;

    select coalesce(v_auth_ids, array[]::uuid[])
           || coalesce(array_agg(distinct e.user_id), array[]::uuid[])
    into v_auth_ids
    from public.employees e
    where e.id = any (v_emp_ids)
      and e.user_id is not null;

    select coalesce(array_agg(distinct x), array[]::uuid[])
    into v_auth_ids
    from unnest(v_auth_ids) as x
    where x is not null;

    raise notice '  employees=% auth_users=%',
      coalesce(array_length(v_emp_ids, 1), 0),
      coalesce(array_length(v_auth_ids, 1), 0);

    if coalesce(array_length(v_emp_ids, 1), 0) > 0 then
      delete from public.employee_assignments a
      where a.employee_id = any (v_emp_ids);

      delete from public.employee_activity_events a
      where a.employee_id = any (v_emp_ids);

      delete from public.employee_invites i
      where i.employee_id = any (v_emp_ids)
         or lower(trim(i.email)) = v_norm;

      delete from public.customer_visits v
      where v.employee_id = any (v_emp_ids);

      delete from public.scheduled_visits v
      where v.employee_id = any (v_emp_ids);

      delete from public.notifications n
      where n.recipient_employee_id = any (v_emp_ids)
         or n.actor_employee_id = any (v_emp_ids);

      delete from public.notification_preferences np
      where np.employee_id = any (v_emp_ids);

      delete from public.employees e
      where e.id = any (v_emp_ids);

      get diagnostics v_n = row_count;
      raise notice '  deleted employees=%', v_n;
    else
      delete from public.employee_invites i
      where lower(trim(i.email)) = v_norm;
    end if;

    if coalesce(array_length(v_auth_ids, 1), 0) > 0 then
      update public.employees e
      set user_id = null
      where e.user_id = any (v_auth_ids);

      delete from public.pending_business_provisions p
      where p.auth_user_id = any (v_auth_ids);

      delete from auth.users u
      where u.id = any (v_auth_ids);

      get diagnostics v_n = row_count;
      raise notice '  deleted auth.users=%', v_n;
    end if;

    if exists (
      select 1 from auth.users u where lower(u.email) = v_norm
    ) then
      raise exception
        'auth.users still has % after delete — rolling back', v_norm;
    end if;

    if exists (
      select 1 from public.employees e where lower(trim(e.email)) = v_norm
    ) then
      raise exception
        'employees still has % after delete — rolling back', v_norm;
    end if;
  end loop;

  raise notice 'Done. Re-invite from Team with fresh email links.';
end $$;

-- Expect: 0 rows
select 'auth.users' as source, email::text as email
from auth.users
where lower(email) in ('velvetkutty@gmail.com', 'angelayra0313@gmail.com')
union all
select 'employees', email
from public.employees
where lower(trim(email)) in ('velvetkutty@gmail.com', 'angelayra0313@gmail.com')
union all
select 'employee_invites', email
from public.employee_invites
where lower(trim(email)) in ('velvetkutty@gmail.com', 'angelayra0313@gmail.com');

commit;
