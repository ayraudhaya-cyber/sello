-- =============================================================================
-- cleanup_test_account.sql
-- One-off / internal diagnostic. NOT a migration. Does not change schema.
--
-- Completely removes ONE test signup (Auth + optional tenant) so the same
-- email can repeat /onboarding from a clean state.
--
-- HOW TO USE (Supabase SQL Editor, Sello project, postgres / service role)
--   1. Edit CONFIG below (email + v_execute).
--   2. Run the entire script with v_execute := false  → preview only.
--   3. Inspect the result grid + notices.
--   4. Set v_execute := true and run again          → deletes inside a txn.
--
-- PROTECTED (never delete):
--   Unitech  0d6f56ac-853c-4634-ab4d-e8882a2b7f3d
--
-- Storage: intentionally untouched (storage.objects deletes are restricted).
-- =============================================================================

begin;

do $$
declare
  -- ============================================================
  -- CONFIG — edit these two only
  -- ============================================================
  v_email text := 'ayramehi98@gmail.com';
  -- Set to true only when ready to actually delete.
  v_execute boolean := false;
  -- ============================================================

  v_keep constant uuid := '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d';
  v_email_norm text;
  v_auth_id uuid;
  v_auth_email text;
  v_company_id uuid;
  v_company_name text;
  v_company_code text;
  v_company_count integer;
  v_company_list text;
  v_keep_present boolean;
  v_row text;
begin
  v_email_norm := lower(trim(coalesce(v_email, '')));
  if v_email_norm = '' then
    raise exception 'CONFIG: v_email is blank';
  end if;

  v_keep_present := exists (
    select 1 from public.companies c where c.id = v_keep
  );
  if not v_keep_present then
    raise exception
      'Protected Unitech company % is missing — refusing to run without keep guard',
      v_keep;
  end if;

  drop table if exists _sello_cleanup_report;
  create temporary table _sello_cleanup_report (
    sort_key integer not null,
    section text not null,
    key text not null,
    value text
  ) on commit drop;

  drop table if exists _sello_cleanup_companies;
  create temporary table _sello_cleanup_companies (
    id uuid primary key,
    name text not null,
    company_code text
  ) on commit drop;

  drop table if exists _sello_cleanup_auth;
  create temporary table _sello_cleanup_auth (
    id uuid primary key,
    email text
  ) on commit drop;

  -- -------------------------------------------------------------------------
  -- Resolve Auth user (required)
  -- -------------------------------------------------------------------------
  select u.id, u.email
  into v_auth_id, v_auth_email
  from auth.users u
  where lower(u.email) = v_email_norm
  limit 1;

  if v_auth_id is null then
    raise exception
      'No Auth user found for email %. Nothing deleted.',
      v_email_norm;
  end if;

  insert into _sello_cleanup_auth (id, email)
  values (v_auth_id, v_auth_email);

  -- -------------------------------------------------------------------------
  -- Resolve companies linked to this Auth user / email
  -- (user_id match, or same-email employee rows for mid-invite orphans)
  -- -------------------------------------------------------------------------
  insert into _sello_cleanup_companies (id, name, company_code)
  select distinct c.id, c.name, c.company_code
  from public.employees e
  join public.companies c on c.id = e.company_id
  where e.user_id = v_auth_id
     or lower(trim(e.email)) = v_email_norm;

  select count(*), string_agg(name || ' (' || id::text || ')', ', ' order by name)
  into v_company_count, v_company_list
  from _sello_cleanup_companies;

  if v_company_count > 1 then
    raise exception
      'Email % is linked to % companies — refusing to guess: %. Nothing deleted.',
      v_email_norm, v_company_count, v_company_list;
  end if;

  if v_company_count = 1 then
    select id, name, company_code
    into v_company_id, v_company_name, v_company_code
    from _sello_cleanup_companies;

    if v_company_id = v_keep then
      raise exception
        'Email % belongs to protected Unitech (%). Nothing deleted.',
        v_email_norm, v_keep;
    end if;

    if lower(trim(v_company_name)) = 'unitech'
       or lower(trim(coalesce(v_company_code, ''))) = 'unitech' then
      raise exception
        'Resolved company looks like Unitech (name=%, code=%). Nothing deleted.',
        v_company_name, v_company_code;
    end if;
  end if;

  -- Auth user must not also be linked to Unitech under another path
  if exists (
    select 1
    from public.employees e
    where e.user_id = v_auth_id
      and e.company_id = v_keep
  ) then
    raise exception
      'Auth user % is linked to protected Unitech. Nothing deleted.',
      v_auth_id;
  end if;

  -- When wiping a tenant, also remove other Auth users that exist only on
  -- that company (e.g. invited Sales Reps), never Unitech-linked users.
  if v_company_id is not null then
    insert into _sello_cleanup_auth (id, email)
    select distinct e.user_id, e.email
    from public.employees e
    where e.company_id = v_company_id
      and e.user_id is not null
      and e.user_id not in (
        select user_id
        from public.employees
        where company_id = v_keep
          and user_id is not null
      )
    on conflict (id) do nothing;
  end if;

  -- -------------------------------------------------------------------------
  -- Preview / audit counts
  -- -------------------------------------------------------------------------
  insert into _sello_cleanup_report (sort_key, section, key, value) values
    (10, 'config', 'email', v_email_norm),
    (11, 'config', 'execute', v_execute::text),
    (12, 'config', 'mode', case when v_execute then 'DELETE' else 'PREVIEW' end),
    (20, 'auth', 'auth_user_id', v_auth_id::text),
    (21, 'auth', 'auth_email', v_auth_email),
    (30, 'company', 'company_id', coalesce(v_company_id::text, '(none — incomplete signup)')),
    (31, 'company', 'company_name', coalesce(v_company_name, '(none)')),
    (32, 'company', 'company_code', coalesce(v_company_code, '(none)')),
    (40, 'keep', 'unitech_id', v_keep::text),
    (41, 'keep', 'unitech_present_before', 'yes');

  insert into _sello_cleanup_report (sort_key, section, key, value)
  select 50, 'counts', 'employees',
    count(*)::text
  from public.employees e
  where (v_company_id is not null and e.company_id = v_company_id)
     or e.user_id = v_auth_id
     or lower(trim(e.email)) = v_email_norm;

  if v_company_id is not null then
    insert into _sello_cleanup_report (sort_key, section, key, value)
    select * from (
      select 51, 'counts', 'branches',
        (select count(*)::text from public.branches b where b.company_id = v_company_id)
      union all select 52, 'counts', 'products',
        (select count(*)::text from public.products p where p.company_id = v_company_id)
      union all select 53, 'counts', 'product_images',
        (select count(*)::text from public.product_images i where i.company_id = v_company_id)
      union all select 54, 'counts', 'product_suppliers',
        (select count(*)::text from public.product_suppliers ps where ps.company_id = v_company_id)
      union all select 55, 'counts', 'categories',
        (select count(*)::text from public.categories c where c.company_id = v_company_id)
      union all select 56, 'counts', 'customers',
        (select count(*)::text from public.customers c where c.company_id = v_company_id)
      union all select 57, 'counts', 'orders',
        (select count(*)::text from public.orders o where o.company_id = v_company_id)
      union all select 58, 'counts', 'order_items',
        (select count(*)::text from public.order_items i where i.company_id = v_company_id)
      union all select 59, 'counts', 'inventory',
        (select count(*)::text from public.inventory i where i.company_id = v_company_id)
      union all select 60, 'counts', 'stock_movements',
        (select count(*)::text from public.stock_movements m where m.company_id = v_company_id)
      union all select 61, 'counts', 'payments',
        (select count(*)::text from public.payments p where p.company_id = v_company_id)
      union all select 62, 'counts', 'payment_allocations',
        (select count(*)::text from public.payment_allocations a where a.company_id = v_company_id)
      union all select 63, 'counts', 'suppliers',
        (select count(*)::text from public.suppliers s where s.company_id = v_company_id)
      union all select 64, 'counts', 'scheduled_visits',
        (select count(*)::text from public.scheduled_visits v where v.company_id = v_company_id)
      union all select 65, 'counts', 'customer_visits',
        (select count(*)::text from public.customer_visits v where v.company_id = v_company_id)
      union all select 66, 'counts', 'employee_assignments',
        (select count(*)::text from public.employee_assignments a where a.company_id = v_company_id)
      union all select 67, 'counts', 'employee_activity_events',
        (select count(*)::text from public.employee_activity_events a where a.company_id = v_company_id)
      union all select 68, 'counts', 'employee_invites',
        (select count(*)::text from public.employee_invites i where i.company_id = v_company_id)
      union all select 69, 'counts', 'company_settings',
        (select count(*)::text from public.company_settings s where s.company_id = v_company_id)
      union all select 70, 'counts', 'company_subscriptions',
        (select count(*)::text from public.company_subscriptions s where s.company_id = v_company_id)
      union all select 71, 'counts', 'company_product_fields',
        (select count(*)::text from public.company_product_fields f where f.company_id = v_company_id)
      union all select 72, 'counts', 'notifications',
        (select count(*)::text from public.notifications n where n.company_id = v_company_id)
      union all select 73, 'counts', 'notification_preferences',
        (select count(*)::text from public.notification_preferences n where n.company_id = v_company_id)
      union all select 74, 'counts', 'company_activity_events',
        (select count(*)::text from public.company_activity_events a where a.company_id = v_company_id)
      union all select 75, 'counts', 'audit_events',
        (select count(*)::text from public.audit_events a where a.company_id = v_company_id)
      union all select 76, 'counts', 'device_registrations',
        (select count(*)::text from public.device_registrations d where d.company_id = v_company_id)
      union all select 77, 'counts', 'document_access_tokens',
        (select count(*)::text from public.document_access_tokens d where d.company_id = v_company_id)
      union all select 78, 'counts', 'outbound_notification_events',
        (select count(*)::text from public.outbound_notification_events e where e.company_id = v_company_id)
      union all select 79, 'counts', 'role_module_access',
        (select count(*)::text from public.role_module_access r where r.company_id = v_company_id)
    ) x(sort_key, section, key, value);
  else
    insert into _sello_cleanup_report (sort_key, section, key, value) values
      (51, 'counts', 'tenant_tables', 'skipped — no company resolved');
  end if;

  insert into _sello_cleanup_report (sort_key, section, key, value)
  select 80, 'counts', 'pending_business_provisions',
    count(*)::text
  from public.pending_business_provisions p
  where p.auth_user_id = v_auth_id
     or lower(trim(p.owner_email)) = v_email_norm;

  insert into _sello_cleanup_report (sort_key, section, key, value)
  select 81, 'counts', 'sello_tenant_invites',
    count(*)::text
  from public.sello_tenant_invites i
  where lower(trim(i.email)) = v_email_norm;

  insert into _sello_cleanup_report (sort_key, section, key, value)
  select 82, 'counts', 'auth_users_to_remove',
    count(*)::text
  from _sello_cleanup_auth;

  insert into _sello_cleanup_report (sort_key, section, key, value)
  select 83, 'auth_users', coalesce(email, id::text), id::text
  from _sello_cleanup_auth
  order by email nulls last;

  -- -------------------------------------------------------------------------
  -- PREVIEW — stop before any mutation
  -- -------------------------------------------------------------------------
  if not v_execute then
    insert into _sello_cleanup_report (sort_key, section, key, value) values
      (5, 'status', 'result', 'PREVIEW ONLY — NOTHING WAS DELETED.');
    raise notice 'PREVIEW ONLY — NOTHING WAS DELETED.';
    raise notice 'email=% auth=% company=% (%)',
      v_email_norm, v_auth_id, coalesce(v_company_id::text, 'none'),
      coalesce(v_company_name, 'n/a');
    return;
  end if;

  -- -------------------------------------------------------------------------
  -- EXECUTE — delete discovered tenant (if any), then auth cleanup
  -- -------------------------------------------------------------------------
  raise notice 'EXECUTE: deleting email=% auth=% company=%',
    v_email_norm, v_auth_id, coalesce(v_company_id::text, 'none');

  if v_company_id is not null then
    update public.companies
    set current_subscription_id = null
    where id = v_company_id;

    delete from public.payment_allocations
    where company_id = v_company_id;

    delete from public.payments
    where company_id = v_company_id;

    delete from public.order_items
    where company_id = v_company_id;

    delete from public.orders
    where company_id = v_company_id;

    delete from public.stock_movements
    where company_id = v_company_id;

    delete from public.inventory
    where company_id = v_company_id;

    delete from public.product_suppliers
    where company_id = v_company_id;

    delete from public.product_images
    where company_id = v_company_id;

    delete from public.products
    where company_id = v_company_id;

    delete from public.categories
    where company_id = v_company_id;

    delete from public.customer_visits
    where company_id = v_company_id;

    delete from public.scheduled_visits
    where company_id = v_company_id;

    delete from public.customers
    where company_id = v_company_id;

    delete from public.suppliers
    where company_id = v_company_id;

    delete from public.employee_assignments
    where company_id = v_company_id;

    delete from public.employee_activity_events
    where company_id = v_company_id;

    delete from public.employees
    where company_id = v_company_id;

    delete from public.branches
    where company_id = v_company_id;

    -- CASCADE from companies:
    -- company_settings, company_subscriptions, company_product_fields,
    -- notifications, notification_preferences, company_activity_events,
    -- audit_events, device_registrations, employee_invites,
    -- role_module_access (tenant rows), document_access_tokens,
    -- outbound_notification_events (+ dispatches via event_id)
    delete from public.companies
    where id = v_company_id;

    if exists (select 1 from public.companies where id = v_company_id) then
      raise exception 'Target company % still exists after delete — rolling back',
        v_company_id;
    end if;
  else
    -- Incomplete signup: remove any orphan employee rows for this email
    -- that are not on Unitech (should be rare / none).
    delete from public.employee_assignments a
    using public.employees e
    where a.employee_id = e.id
      and lower(trim(e.email)) = v_email_norm
      and e.company_id is distinct from v_keep;

    delete from public.employee_activity_events a
    using public.employees e
    where a.employee_id = e.id
      and lower(trim(e.email)) = v_email_norm
      and e.company_id is distinct from v_keep;

    delete from public.employee_invites i
    where lower(trim(i.email)) = v_email_norm
      and (i.company_id is null or i.company_id is distinct from v_keep);

    delete from public.employees e
    where lower(trim(e.email)) = v_email_norm
      and e.company_id is distinct from v_keep;
  end if;

  delete from public.pending_business_provisions p
  where p.auth_user_id in (select id from _sello_cleanup_auth)
     or lower(trim(p.owner_email)) = v_email_norm;

  -- Re-open invite so the same email can sign up again (do not delete the row).
  update public.sello_tenant_invites i
  set status = 'approved',
      used_at = null
  where lower(trim(i.email)) = v_email_norm;

  -- Final Unitech / auth-link guard before touching auth.users
  if exists (
    select 1
    from public.employees e
    where e.user_id in (select id from _sello_cleanup_auth)
      and e.company_id = v_keep
  ) then
    raise exception
      'Refusing auth.users delete — user still linked to Unitech — rolling back';
  end if;

  if not exists (select 1 from public.companies where id = v_keep) then
    raise exception 'Unitech keep company disappeared — rolling back';
  end if;

  delete from auth.users
  where id in (select id from _sello_cleanup_auth);

  if exists (select 1 from auth.users where id = v_auth_id) then
    raise exception 'Target Auth user % still exists — rolling back', v_auth_id;
  end if;

  if exists (
    select 1
    from public.pending_business_provisions p
    where p.auth_user_id = v_auth_id
       or lower(trim(p.owner_email)) = v_email_norm
  ) then
    raise exception 'pending_business_provisions still present — rolling back';
  end if;

  if not exists (select 1 from public.companies where id = v_keep) then
    raise exception 'Unitech keep company missing after auth delete — rolling back';
  end if;

  insert into _sello_cleanup_report (sort_key, section, key, value) values
    (5, 'status', 'result', 'EXECUTE complete — tenant/auth removed; Storage untouched.'),
    (6, 'status', 'storage', 'Storage objects (if any) were NOT deleted — clean via Storage API/UI if needed.'),
    (42, 'keep', 'unitech_present_after', 'yes');

  raise notice 'EXECUTE complete for %. Unitech % still present. Storage left untouched.',
    v_email_norm, v_keep;
end $$;

-- Result grid (preview or post-execute summary)
select section, key, value
from _sello_cleanup_report
order by sort_key, key;

-- Explicit keep check for the Results tab
select
  id,
  name,
  company_code,
  'KEEP — must remain' as note
from public.companies
where id = '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d';

commit;
