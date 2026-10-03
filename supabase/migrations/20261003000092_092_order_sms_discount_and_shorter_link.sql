-- =============================================================================
-- 092 — Sale SMS can see the discount, and new invoice links are shorter
--
-- prepare_order_confirmation now returns orders.discount_amount (the resolved
-- discount). New document tokens are 32-character base64url instead of 48-character
-- hex. Existing links keep working. The token stays opaque and unguessable.
-- =============================================================================

create or replace function public.prepare_order_confirmation(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_employee_id uuid;
  v_order public.orders%rowtype;
  v_token text;
  v_token_id uuid;
  v_event_id uuid;
  v_already boolean := false;
  v_customer jsonb;
  v_hub jsonb;
  v_sales_rep jsonb;
  v_company_name text;
  v_rep_name text;
  v_currency text;
begin
  v_employee_id := public.current_employee_id();
  v_company_id := public.current_company_id();
  if v_employee_id is null or v_company_id is null then
    raise exception 'Session context missing.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
    and company_id = v_company_id
    and deleted_at is null;

  if not found then
    raise exception 'Order not found.';
  end if;

  if v_order.status not in ('placed', 'partially_delivered', 'completed') then
    raise exception 'Order confirmation is available after the order is submitted.';
  end if;

  select t.id, t.token into v_token_id, v_token
  from public.document_access_tokens t
  where t.order_id = v_order.id
    and t.purpose = 'order_confirmation'
    and t.revoked_at is null
    and (t.expires_at is null or t.expires_at > timezone('utc', now()))
  limit 1;

  if v_token is null then
    -- 24 bytes, base64url, no padding: 32 characters (was 48 hex).
    v_token := translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_');
    insert into public.document_access_tokens (
      company_id,
      order_id,
      purpose,
      token,
      created_by,
      expires_at
    ) values (
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
  ) values (
    v_company_id,
    'order_confirmation',
    'order',
    v_order.id,
    v_token_id
  )
  on conflict (event_type, reference_type, reference_id) do nothing;

  select e.id, e.created_at < timezone('utc', now()) - interval '1 second'
  into v_event_id, v_already
  from public.outbound_notification_events e
  where e.event_type = 'order_confirmation'
    and e.reference_type = 'order'
    and e.reference_id = v_order.id;

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
  where c.id = v_order.customer_id
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
    and r.code in ('owner', 'manager', 'administrator')
    and e.id is distinct from v_employee_id;

  select jsonb_build_object(
    'id', e.id,
    'name', e.full_name,
    'phone', e.phone
  )
  into v_sales_rep
  from public.employees e
  where e.id = v_order.employee_id
    and e.company_id = v_company_id
    and e.deleted_at is null;

  select co.name into v_company_name
  from public.companies co
  where co.id = v_company_id;

  v_rep_name := v_sales_rep ->> 'name';

  select cs.currency into v_currency
  from public.company_settings cs
  where cs.company_id = v_company_id;

  return jsonb_build_object(
    'already_prepared', coalesce(v_already, false),
    'event_id', v_event_id,
    'token', v_token,
    'order', jsonb_build_object(
      'number', v_order.order_number,
      'ordered_at', v_order.ordered_at,
      'completed_at', v_order.completed_at,
      'total', v_order.total,
      'discount_amount', coalesce(v_order.discount_amount, 0),
      'currency', coalesce(v_currency, 'USD'),
      'customer_name', v_customer ->> 'name',
      'sales_rep_name', v_rep_name,
      'company_name', v_company_name
    ),
    'customer', coalesce(v_customer, 'null'::jsonb),
    'hub_recipients', coalesce(v_hub, '[]'::jsonb),
    'sales_rep', coalesce(v_sales_rep, 'null'::jsonb)
  );
end;
$$;

comment on function public.prepare_order_confirmation(uuid) is
  'Issues or reuses an opaque order-confirmation token for placed, '
  'partially delivered, or completed orders. Includes the resolved discount.';
