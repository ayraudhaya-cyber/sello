-- 094: Collection notices for the team on every recorded collection,
--      and a safe "update my own profile" RPC.
--
-- 1. prepare_collection_acknowledgement now also accepts COMPLETED
--    collections (previously only pending-review). Same event / token shape,
--    so the pending flow is unchanged. Hub recipients are every active
--    Owner / Manager / Administrator, excluding the person who recorded the
--    collection UNLESS nobody else would be left (single-owner businesses).
-- 2. update_my_profile — an employee can change only their own name and
--    mobile number. No role, email, company, or status changes.

-- ---------------------------------------------------------------------------
-- 1. prepare_collection_acknowledgement
-- ---------------------------------------------------------------------------

create or replace function public.prepare_collection_acknowledgement(
  p_payment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_employee_id uuid;
  v_payment public.payments%rowtype;
  v_token text;
  v_token_id uuid;
  v_event_id uuid;
  v_already boolean := false;
  v_customer jsonb;
  v_hub jsonb;
  v_company_name text;
  v_rep_name text;
  v_currency text;
begin
  v_employee_id := public.current_employee_id();
  v_company_id := public.current_company_id();
  if v_employee_id is null or v_company_id is null then
    raise exception 'Session context missing.';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id
    and company_id = v_company_id
    and deleted_at is null;

  if not found then
    raise exception 'Payment not found.';
  end if;

  if v_payment.status not in ('pending', 'completed') then
    raise exception
      'Collection notices are only for recorded or pending-review collections.';
  end if;

  select t.id, t.token into v_token_id, v_token
  from public.document_access_tokens t
  where t.payment_id = v_payment.id
    and t.purpose = 'collection_acknowledgement'
    and t.revoked_at is null
    and (t.expires_at is null or t.expires_at > timezone('utc', now()))
  limit 1;

  if v_token is null then
    v_token := encode(gen_random_bytes(24), 'hex');
    insert into public.document_access_tokens (
      company_id,
      payment_id,
      purpose,
      token,
      created_by,
      expires_at
    ) values (
      v_company_id,
      v_payment.id,
      'collection_acknowledgement',
      v_token,
      v_employee_id,
      timezone('utc', now()) + interval '365 days'
    )
    returning id into v_token_id;
  end if;

  insert into public.outbound_notification_events (
    company_id,
    event_type,
    reference_type,
    reference_id,
    document_token_id
  ) values (
    v_company_id,
    'collection_acknowledgement',
    'payment',
    v_payment.id,
    v_token_id
  )
  on conflict (event_type, reference_type, reference_id) do nothing;

  select e.id, e.created_at < timezone('utc', now()) - interval '1 second'
  into v_event_id, v_already
  from public.outbound_notification_events e
  where e.event_type = 'collection_acknowledgement'
    and e.reference_type = 'payment'
    and e.reference_id = v_payment.id;

  if v_event_id is not null
     and exists (
       select 1
       from public.outbound_notification_dispatches d
       where d.event_id = v_event_id
     ) then
    v_already := true;
  end if;

  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'phone', c.phone,
    'whatsapp', c.whatsapp
  )
  into v_customer
  from public.customers c
  where c.id = v_payment.customer_id
    and c.company_id = v_company_id
    and c.deleted_at is null;

  -- Team recipients, leaving out the person who recorded it…
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'name', e.full_name,
        'role', r.code,
        'phone', e.phone
      )
      order by r.code, e.full_name
    ),
    '[]'::jsonb
  )
  into v_hub
  from public.employees e
  join public.roles r on r.id = e.role_id
  where e.company_id = v_company_id
    and e.deleted_at is null
    and e.employment_status = 'active'
    and r.code in ('owner', 'manager', 'administrator')
    and e.id is distinct from v_employee_id;

  -- …unless that leaves nobody (e.g. a one-owner business).
  if jsonb_array_length(v_hub) = 0 then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'name', e.full_name,
          'role', r.code,
          'phone', e.phone
        )
        order by r.code, e.full_name
      ),
      '[]'::jsonb
    )
    into v_hub
    from public.employees e
    join public.roles r on r.id = e.role_id
    where e.company_id = v_company_id
      and e.deleted_at is null
      and e.employment_status = 'active'
      and r.code in ('owner', 'manager', 'administrator');
  end if;

  select co.name into v_company_name
  from public.companies co
  where co.id = v_company_id;

  select emp.full_name into v_rep_name
  from public.employees emp
  where emp.id = v_payment.employee_id;

  select cs.currency into v_currency
  from public.company_settings cs
  where cs.company_id = v_company_id;

  return jsonb_build_object(
    'already_prepared', coalesce(v_already, false),
    'event_id', v_event_id,
    'token', v_token,
    'payment', jsonb_build_object(
      'number', v_payment.payment_number,
      'amount', v_payment.amount,
      'method', v_payment.method,
      'status', v_payment.status,
      'received_at', v_payment.received_at,
      'reference', v_payment.reference,
      'notes', v_payment.notes,
      'currency', coalesce(v_currency, 'USD'),
      'customer_name', v_customer ->> 'name',
      'sales_rep_name', v_rep_name,
      'company_name', v_company_name
    ),
    'customer', coalesce(v_customer, 'null'::jsonb),
    'hub_recipients', coalesce(v_hub, '[]'::jsonb)
  );
end;
$$;

comment on function public.prepare_collection_acknowledgement(uuid) is
  'Issues a collection notice token and team recipient snapshot for a pending '
  'or completed collection. Does not change balances.';

grant execute on function public.prepare_collection_acknowledgement(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. update_my_profile
-- ---------------------------------------------------------------------------

create or replace function public.update_my_profile(
  p_full_name text,
  p_phone text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  before_name text;
  before_phone text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if v_name is null then
    raise exception 'Name is required.';
  end if;

  if v_phone is not null and length(v_phone) > 32 then
    raise exception 'Enter a valid mobile number.';
  end if;

  select e.full_name, e.phone
  into before_name, before_phone
  from public.employees e
  where e.id = emp
    and e.company_id = company
    and e.deleted_at is null
  for update;

  if not found then
    raise exception 'Profile not found.';
  end if;

  if before_name is not distinct from v_name
     and before_phone is not distinct from v_phone then
    return;
  end if;

  update public.employees
  set
    full_name = v_name,
    phone = v_phone,
    updated_by = emp
  where id = emp
    and company_id = company;

  perform public.log_company_activity(
    company,
    'team',
    'profile_updated',
    v_name || ' updated their profile',
    emp,
    null,
    'employee',
    emp,
    jsonb_build_object(
      'name_changed', before_name is distinct from v_name,
      'phone_changed', before_phone is distinct from v_phone
    )
  );
end;
$$;

comment on function public.update_my_profile(text, text) is
  'Lets the signed-in employee change only their own name and mobile number.';

revoke all on function public.update_my_profile(text, text) from public;
grant execute on function public.update_my_profile(text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('public.update_my_profile(text, text)') is null then
    raise exception '094: update_my_profile missing';
  end if;
  if to_regprocedure('public.prepare_collection_acknowledgement(uuid)') is null then
    raise exception '094: prepare_collection_acknowledgement missing';
  end if;
end;
$$;
