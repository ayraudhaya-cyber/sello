-- 095: Collection notices — let the business choose whether the team is told
--      about collections that an Owner / Manager records themselves.
--
-- prepare_collection_acknowledgement (from 094) now:
--   * returns EVERY active Owner / Manager / Administrator as a recipient
--     (the recorder is no longer left out), and
--   * returns `recorded_by_team` (true when the person who recorded the
--     collection is an Owner / Manager / Administrator).
--
-- The app then applies the tenant setting
-- `outbound_notification_policies.types.collection_submitted.notify_when_team_records`
-- (Settings → Notifications). Collections recorded by a Sales Rep always
-- notify the team.

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
  v_recorded_by_team boolean := false;
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

  select exists (
    select 1
    from public.employees e
    join public.roles r on r.id = e.role_id
    where e.id = v_payment.employee_id
      and e.company_id = v_company_id
      and r.code in ('owner', 'manager', 'administrator')
  )
  into v_recorded_by_team;

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
    'recorded_by_team', coalesce(v_recorded_by_team, false),
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
  'or completed collection, and says whether the team recorded it themselves. '
  'Does not change balances.';

grant execute on function public.prepare_collection_acknowledgement(uuid)
  to authenticated;

do $$
begin
  if to_regprocedure('public.prepare_collection_acknowledgement(uuid)') is null then
    raise exception '095: prepare_collection_acknowledgement missing';
  end if;
end;
$$;
