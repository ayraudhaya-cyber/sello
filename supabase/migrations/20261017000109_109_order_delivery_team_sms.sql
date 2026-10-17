-- Allow the delivery SMS policy to target active Owners / Managers as well
-- as the buyer. Existing tenant choices remain unchanged until enabled in
-- Settings > Notifications.

create or replace function public.prepare_order_delivery_notification(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid := public.current_company_id();
  v_employee_id uuid := public.current_employee_id();
  v_order public.orders%rowtype;
  v_delivery_id uuid;
  v_event_id uuid;
  v_token_id uuid;
  v_token text;
  v_customer jsonb;
  v_hub jsonb;
  v_company_name text;
  v_actor_name text;
begin
  if v_company_id is null or v_employee_id is null then
    raise exception 'Session context missing.';
  end if;

  select * into v_order
  from public.orders o
  where o.id = p_order_id
    and o.company_id = v_company_id
    and o.deleted_at is null;

  if not found then
    raise exception 'Order not found.';
  end if;

  if v_order.status not in ('partially_delivered', 'completed') then
    raise exception 'No recorded delivery is available for this order.';
  end if;

  if v_order.updated_by is distinct from v_employee_id
     or v_order.updated_at < timezone('utc', now()) - interval '5 minutes' then
    raise exception 'Delivery notification window has expired.';
  end if;

  insert into public.order_delivery_notification_events (
    company_id,
    order_id,
    order_updated_at,
    recorded_by
  )
  values (
    v_company_id,
    v_order.id,
    v_order.updated_at,
    v_employee_id
  )
  on conflict (order_id, order_updated_at) do nothing;

  select d.id into v_delivery_id
  from public.order_delivery_notification_events d
  where d.order_id = v_order.id
    and d.order_updated_at = v_order.updated_at;

  select t.id, t.token into v_token_id, v_token
  from public.document_access_tokens t
  where t.order_id = v_order.id
    and t.purpose = 'order_confirmation'
    and t.revoked_at is null
    and (t.expires_at is null or t.expires_at > timezone('utc', now()))
  limit 1;

  if v_token is null then
    v_token := public.new_document_access_token();
    insert into public.document_access_tokens (
      company_id,
      order_id,
      purpose,
      token,
      created_by,
      expires_at
    )
    values (
      v_company_id,
      v_order.id,
      'order_confirmation',
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
  )
  values (
    v_company_id,
    'order_delivery',
    'order_delivery',
    v_delivery_id,
    v_token_id
  )
  on conflict (event_type, reference_type, reference_id) do nothing;

  select e.id into v_event_id
  from public.outbound_notification_events e
  where e.event_type = 'order_delivery'
    and e.reference_type = 'order_delivery'
    and e.reference_id = v_delivery_id;

  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'phone', c.phone,
    'whatsapp', c.whatsapp
  )
  into v_customer
  from public.customers c
  where c.id = v_order.customer_id
    and c.company_id = v_company_id
    and c.deleted_at is null;

  -- Do not text the person who recorded the delivery when another active
  -- Owner / Manager is available. Single-owner businesses still work.
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

  select e.full_name into v_actor_name
  from public.employees e
  where e.id = v_employee_id
    and e.company_id = v_company_id;

  return jsonb_build_object(
    'event_id', v_event_id,
    'token', v_token,
    'order_number', v_order.order_number,
    'company_name', v_company_name,
    'delivery_status', case
      when v_order.status = 'completed' then 'fully delivered'
      else 'partially delivered'
    end,
    'recorded_by_name', v_actor_name,
    'customer', coalesce(v_customer, 'null'::jsonb),
    'hub_recipients', coalesce(v_hub, '[]'::jsonb)
  );
end;
$$;

comment on function public.prepare_order_delivery_notification(uuid) is
  'Prepares one idempotent delivery SMS event with buyer and team recipients.';

revoke all on function public.prepare_order_delivery_notification(uuid)
  from public;
grant execute on function public.prepare_order_delivery_notification(uuid)
  to authenticated;
