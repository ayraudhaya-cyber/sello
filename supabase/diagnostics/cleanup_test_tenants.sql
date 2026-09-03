-- =============================================================================
-- One-off cleanup for signup/onboarding TEST tenants
-- Paste into Supabase SQL Editor. NOT a migration. Does not change schema.
--
-- KEEP (never delete):
--   Unitech
--   0d6f56ac-853c-4634-ab4d-e8882a2b7f3d
--
-- TARGET NAMES (matched after stripping spaces/punctuation, case-insensitive):
--   AYRA INN, Rio, UnitechSolutions (also "Unitech Solutions")
--
-- HOW TO USE
--   1. Run Section A (preview) and read the result sets.
--   2. Confirm Unitech is absent from the target list.
--   3. Only then run Section B (delete) in the same session / as postgres.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Shared target selector (edit names here if a match is wrong)
-- ---------------------------------------------------------------------------
-- Run this once to inspect matches:
--   select * from ...  (see Section A)

-- =============================================================================
-- SECTION A — PREVIEW ONLY (run this first; it deletes nothing)
-- =============================================================================

-- A1. Live FK map: every constraint that references public.companies(id)
select
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
 and kcu.constraint_schema = tc.constraint_schema
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
 and rc.constraint_schema = tc.constraint_schema
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = rc.unique_constraint_name
 and ccu.constraint_schema = rc.unique_constraint_schema
where tc.constraint_type = 'FOREIGN KEY'
  and ccu.table_schema = 'public'
  and ccu.table_name = 'companies'
  and ccu.column_name = 'id'
order by rc.delete_rule, tc.table_name, kcu.column_name;

-- A2. Resolve target companies (must not include Unitech)
with keep as (
  select '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d'::uuid as id
),
targets as (
  select
    c.id,
    c.name,
    c.company_code,
    c.slug,
    c.created_at,
    c.deleted_at,
    lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) as name_key
  from public.companies c
  cross join keep k
  where c.id <> k.id
    and lower(trim(c.name)) <> 'unitech'
    and lower(c.company_code) <> 'unitech'
    and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) in (
      'ayrainn',
      'rio',
      'unitechsolutions'
    )
)
select *
from targets
order by name;

-- A3. Related row counts per target company
with keep as (
  select '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d'::uuid as id
),
targets as (
  select c.id, c.name, c.company_code
  from public.companies c
  cross join keep k
  where c.id <> k.id
    and lower(trim(c.name)) <> 'unitech'
    and lower(c.company_code) <> 'unitech'
    and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) in (
      'ayrainn', 'rio', 'unitechsolutions'
    )
)
select
  t.name,
  t.id as company_id,
  (select count(*) from public.company_settings s where s.company_id = t.id) as company_settings,
  (select count(*) from public.branches b where b.company_id = t.id) as branches,
  (select count(*) from public.employees e where e.company_id = t.id) as employees,
  (select count(*) from public.employees e where e.company_id = t.id and e.user_id is not null) as linked_auth_users,
  (select count(*) from public.customers c where c.company_id = t.id) as customers,
  (select count(*) from public.orders o where o.company_id = t.id) as orders,
  (select count(*) from public.order_items i where i.company_id = t.id) as order_items,
  (select count(*) from public.products p where p.company_id = t.id) as products,
  (select count(*) from public.inventory i where i.company_id = t.id) as inventory,
  (select count(*) from public.stock_movements m where m.company_id = t.id) as stock_movements,
  (select count(*) from public.payments p where p.company_id = t.id) as payments,
  (select count(*) from public.payment_allocations a where a.company_id = t.id) as payment_allocations,
  (select count(*) from public.notifications n where n.company_id = t.id) as notifications,
  (select count(*) from public.document_access_tokens d where d.company_id = t.id) as document_access_tokens,
  (select count(*) from public.outbound_notification_events e where e.company_id = t.id) as outbound_events,
  (select count(*) from public.company_subscriptions cs where cs.company_id = t.id) as company_subscriptions,
  (select count(*) from public.suppliers s where s.company_id = t.id) as suppliers,
  (select count(*) from public.scheduled_visits v where v.company_id = t.id) as scheduled_visits,
  (select count(*) from public.customer_visits v where v.company_id = t.id) as customer_visits,
  (select count(*) from public.employee_invites i where i.company_id = t.id) as employee_invites,
  (select count(*) from public.company_product_fields f where f.company_id = t.id) as company_product_fields,
  (select count(*) from public.audit_events a where a.company_id = t.id) as audit_events
from targets t
order by t.name;

-- A4. Auth users linked to target companies (need a separate auth.users delete)
with keep as (
  select '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d'::uuid as id
),
targets as (
  select c.id, c.name
  from public.companies c
  cross join keep k
  where c.id <> k.id
    and lower(trim(c.name)) <> 'unitech'
    and lower(c.company_code) <> 'unitech'
    and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) in (
      'ayrainn', 'rio', 'unitechsolutions'
    )
)
select
  t.name as company_name,
  e.id as employee_id,
  e.email,
  e.full_name,
  e.user_id as auth_user_id,
  au.email as auth_email,
  au.created_at as auth_created_at
from targets t
join public.employees e on e.company_id = t.id
left join auth.users au on au.id = e.user_id
where e.user_id is not null
order by t.name, e.email;

-- A5. Confirm Unitech is untouched by the selector
select
  c.id,
  c.name,
  c.company_code,
  'KEEP — must not appear in A2' as note
from public.companies c
where c.id = '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d'
   or lower(trim(c.name)) = 'unitech'
   or lower(c.company_code) = 'unitech';

-- A6. Pending provisions / invites for those owner emails (no company_id FK)
with keep as (
  select '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d'::uuid as id
),
target_emails as (
  select lower(trim(e.email)) as email
  from public.employees e
  join public.companies c on c.id = e.company_id
  cross join keep k
  where c.id <> k.id
    and lower(trim(c.name)) <> 'unitech'
    and lower(c.company_code) <> 'unitech'
    and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) in (
      'ayrainn', 'rio', 'unitechsolutions'
    )
)
select 'pending_business_provisions' as source, p.owner_email, p.status, p.business_name
from public.pending_business_provisions p
where lower(p.owner_email) in (select email from target_emails)
union all
select 'sello_tenant_invites', i.email, i.status, i.company_name
from public.sello_tenant_invites i
where i.email in (select email from target_emails);

-- =============================================================================
-- SECTION B — DELETE (run only after A2–A5 look correct)
-- Wrap in a transaction. Abort if Unitech is selected.
-- =============================================================================
/*
begin;

do $$
declare
  v_keep constant uuid := '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d';
  v_count integer;
  v_names text;
begin
  create temporary table _sello_doomed_companies (
    id uuid primary key,
    name text not null
  ) on commit drop;

  create temporary table _sello_doomed_auth_users (
    id uuid primary key,
    email text
  ) on commit drop;

  insert into _sello_doomed_companies (id, name)
  select c.id, c.name
  from public.companies c
  where c.id <> v_keep
    and lower(trim(c.name)) <> 'unitech'
    and lower(c.company_code) <> 'unitech'
    and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) in (
      'ayrainn', 'rio', 'unitechsolutions'
    );

  if exists (select 1 from _sello_doomed_companies where id = v_keep) then
    raise exception 'Refusing to delete Unitech keep id %', v_keep;
  end if;

  select count(*), string_agg(name || ' (' || id::text || ')', ', ')
  into v_count, v_names
  from _sello_doomed_companies;

  if v_count = 0 then
    raise exception 'No matching test companies found. Check names in Section A.';
  end if;

  raise notice 'Deleting % test companies: %', v_count, v_names;

  insert into _sello_doomed_auth_users (id, email)
  select distinct e.user_id, e.email
  from public.employees e
  where e.company_id in (select id from _sello_doomed_companies)
    and e.user_id is not null
    and e.user_id not in (
      select user_id
      from public.employees
      where company_id = v_keep
        and user_id is not null
    );

  -- Break companies ↔ company_subscriptions cycle
  update public.companies
  set current_subscription_id = null
  where id in (select id from _sello_doomed_companies);

  -- RESTRICT children of companies (order matters for nested restrict FKs)
  delete from public.payment_allocations
  where company_id in (select id from _sello_doomed_companies);

  delete from public.payments
  where company_id in (select id from _sello_doomed_companies);

  delete from public.order_items
  where company_id in (select id from _sello_doomed_companies);

  delete from public.orders
  where company_id in (select id from _sello_doomed_companies);

  delete from public.stock_movements
  where company_id in (select id from _sello_doomed_companies);

  delete from public.inventory
  where company_id in (select id from _sello_doomed_companies);

  delete from public.product_suppliers
  where company_id in (select id from _sello_doomed_companies);

  delete from public.product_images
  where company_id in (select id from _sello_doomed_companies);

  delete from public.products
  where company_id in (select id from _sello_doomed_companies);

  delete from public.categories
  where company_id in (select id from _sello_doomed_companies);

  delete from public.customer_visits
  where company_id in (select id from _sello_doomed_companies);

  delete from public.scheduled_visits
  where company_id in (select id from _sello_doomed_companies);

  delete from public.customers
  where company_id in (select id from _sello_doomed_companies);

  delete from public.suppliers
  where company_id in (select id from _sello_doomed_companies);

  delete from public.employee_assignments
  where company_id in (select id from _sello_doomed_companies);

  delete from public.employee_activity_events
  where company_id in (select id from _sello_doomed_companies);

  delete from public.employees
  where company_id in (select id from _sello_doomed_companies);

  delete from public.branches
  where company_id in (select id from _sello_doomed_companies);

  -- Remaining company_id rows CASCADE from this delete:
  -- company_settings, company_subscriptions, company_product_fields,
  -- notifications, notification_preferences, company_activity_events,
  -- audit_events, device_registrations, employee_invites,
  -- role_module_access (tenant rows only), document_access_tokens,
  -- outbound_notification_events (+ dispatches via event_id cascade)
  delete from public.companies
  where id in (select id from _sello_doomed_companies);

  if not exists (
    select 1 from public.companies
    where id = v_keep
  ) then
    raise exception 'Unitech keep company disappeared — rolling back';
  end if;

  -- Storage has no FK. Paths are <company_id>/...
  delete from storage.objects
  where bucket_id in ('product-images', 'employee-avatars', 'company-branding')
    and split_part(name, '/', 1) in (
      select id::text from _sello_doomed_companies
    )
    and split_part(name, '/', 1) <> v_keep::text;

  -- Pending onboarding rows for those auth users (also cascade if auth.users deleted)
  delete from public.pending_business_provisions p
  where p.auth_user_id in (select id from _sello_doomed_auth_users);

  -- Allow the same emails to be invited again for future signup tests
  update public.sello_tenant_invites i
  set
    status = 'approved',
    used_at = null
  where i.email in (
    select lower(trim(email)) from _sello_doomed_auth_users where email is not null
  )
    and i.email not in (
      select lower(trim(e.email))
      from public.employees e
      where e.company_id = v_keep
    );

  -- Auth users are not removed by company FKs (employees.user_id is ON DELETE SET NULL)
  delete from auth.users
  where id in (select id from _sello_doomed_auth_users);

  raise notice 'Cleanup finished. Unitech % still present.', v_keep;
end $$;

-- Confirm keep company still exists
select id, name, company_code
from public.companies
where id = '0d6f56ac-853c-4634-ab4d-e8882a2b7f3d';

commit;
*/
