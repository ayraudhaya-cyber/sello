-- =============================================================================
-- 114 — Surface collection discount on notices and public documents
--
-- Depends on 113 (payments.discount_amount). Collection / receipt SMS and the
-- public collection document show discount separately when it was applied.
-- Order confirmation / invoice SMS already use orders.discount_amount.
-- get_public_document_by_token is based on migration 100, plus discount fields.
-- =============================================================================

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
    v_token := public.new_document_access_token();
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
      'discount_amount', coalesce(v_payment.discount_amount, 0),
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
  'Issues a collection notice token and team recipient snapshot. Includes discount_amount. Does not change balances.';

revoke all on function public.prepare_collection_acknowledgement(uuid) from public;
grant execute on function public.prepare_collection_acknowledgement(uuid) to authenticated;

create or replace function public.prepare_payment_receipt(
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
  v_event_id uuid;
  v_already boolean := false;
  v_customer jsonb;
  v_company_name text;
  v_currency text;
  v_has_opening boolean := false;
  v_references text;
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

  if v_payment.status is distinct from 'completed' then
    return jsonb_build_object(
      'ok', false,
      'reason', 'not_applied',
      'has_opening_allocation', false
    );
  end if;

  select exists (
    select 1
    from public.payment_allocations pa
    where pa.payment_id = v_payment.id
      and pa.receivable_adjustment_id is not null
  )
  into v_has_opening;

  if not coalesce(v_has_opening, false) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'no_opening_allocation',
      'has_opening_allocation', false
    );
  end if;

  select string_agg(refs.reference_number, ', ' order by refs.reference_number)
  into v_references
  from (
    select distinct adj.reference_number
    from public.payment_allocations pa
    inner join public.customer_receivable_adjustments adj
      on adj.id = pa.receivable_adjustment_id
    where pa.payment_id = v_payment.id
      and adj.reference_number is not null
  ) refs;

  insert into public.outbound_notification_events (
    company_id,
    event_type,
    reference_type,
    reference_id
  ) values (
    v_company_id,
    'receipt',
    'payment',
    v_payment.id
  )
  on conflict (event_type, reference_type, reference_id) do nothing;

  select e.id, e.created_at < timezone('utc', now()) - interval '1 second'
  into v_event_id, v_already
  from public.outbound_notification_events e
  where e.event_type = 'receipt'
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

  select co.name into v_company_name
  from public.companies co
  where co.id = v_company_id;

  select cs.currency into v_currency
  from public.company_settings cs
  where cs.company_id = v_company_id;

  return jsonb_build_object(
    'ok', true,
    'already_prepared', coalesce(v_already, false),
    'event_id', v_event_id,
    'has_opening_allocation', true,
    'opening_reference', v_references,
    'payment', jsonb_build_object(
      'number', v_payment.payment_number,
      'amount', v_payment.amount,
      'discount_amount', coalesce(v_payment.discount_amount, 0),
      'method', v_payment.method,
      'status', v_payment.status,
      'received_at', v_payment.received_at,
      'currency', coalesce(v_currency, 'USD'),
      'customer_name', v_customer ->> 'name',
      'company_name', v_company_name
    ),
    'customer', coalesce(v_customer, 'null'::jsonb)
  );
end;
$$;

revoke all on function public.prepare_payment_receipt(uuid) from public;
grant execute on function public.prepare_payment_receipt(uuid) to authenticated;

-- Based on migration 100, plus collection discount fields.
create or replace function public.get_public_document_by_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token public.document_access_tokens%rowtype;
  v_order public.orders%rowtype;
  v_payment public.payments%rowtype;
  v_show_outstanding boolean;
  v_collection jsonb;
  v_payload jsonb;
begin
  if p_token is null or length(trim(p_token)) < 11 then
    return null;
  end if;

  select * into v_token
  from public.document_access_tokens
  where token = trim(p_token)
    and revoked_at is null
    and (expires_at is null or expires_at > timezone('utc', now()));

  if not found then
    return null;
  end if;

  update public.document_access_tokens
  set
    last_viewed_at = timezone('utc', now()),
    view_count = view_count + 1
  where id = v_token.id;

  if v_token.purpose in ('order_confirmation', 'invoice')
     and v_token.order_id is not null then
    select * into v_order
    from public.orders
    where id = v_token.order_id
      and company_id = v_token.company_id
      and deleted_at is null
      and status in ('placed', 'partially_delivered', 'completed');

    if not found then
      return null;
    end if;

    select coalesce(
      (cs.financial_visibility_policies ->> 'outstanding_balance') = 'customer_copy',
      false
    )
    into v_show_outstanding
    from public.company_settings cs
    where cs.company_id = v_order.company_id;

    select jsonb_build_object(
      'review', case
        when p.status = 'pending' then 'processing'
        else 'approved'
      end,
      'payment_number', p.payment_number,
      'method', p.method,
      'amount', pa.amount,
      'discount_amount', coalesce(p.discount_amount, 0),
      'received_at', p.created_at
    )
    into v_collection
    from public.payment_allocations pa
    join public.payments p
      on p.id = pa.payment_id
     and p.company_id = pa.company_id
    where pa.order_id = v_order.id
      and pa.company_id = v_order.company_id
      and p.deleted_at is null
      and (
        p.status = 'pending'
        or (p.status = 'completed' and p.reviewed_at is not null)
      )
    order by
      case when p.status = 'pending' then 0 else 1 end,
      coalesce(p.reviewed_at, p.received_at) desc,
      p.created_at desc
    limit 1;

    select jsonb_build_object(
      'purpose', v_token.purpose,
      'order_number', v_order.order_number,
      'ordered_at', v_order.ordered_at,
      'completed_at', v_order.completed_at,
      'subtotal', v_order.subtotal,
      'discount_amount', v_order.discount_amount,
      'tax_amount', v_order.tax_amount,
      'total', v_order.total,
      'payment_status', v_order.payment_status,
      'payment_method', v_order.payment_method,
      'notes', v_order.notes,
      'company_name', co.name,
      'currency', coalesce(cs.currency, 'USD'),
      'currency_position', coalesce(cs.currency_position, 'before'),
      'document_logo_url', cs.document_logo_url,
      'document_show_business_name_with_logo',
        coalesce(cs.document_show_business_name_with_logo, false),
      'document_address', nullif(trim(cs.document_address), ''),
      'document_phone', nullif(trim(cs.document_phone), ''),
      'document_email', nullif(trim(cs.document_email), ''),
      'document_terms', nullif(trim(cs.document_terms), ''),
      'document_tagline', nullif(trim(cs.document_tagline), ''),
      'document_print_template', coalesce(cs.document_print_template, 'standard'),
      'document_logo_print_black', coalesce(cs.document_logo_print_black, false),
      'document_authorized_signature_url', cs.document_authorized_signature_url,
      'logo_url', case
        when coalesce(cs.custom_branding_enabled, false) then cs.logo_url
        else null
      end,
      'logo_light_url', case
        when coalesce(cs.custom_branding_enabled, false) then cs.logo_light_url
        else null
      end,
      'primary_color', case
        when coalesce(cs.custom_branding_enabled, false) then cs.primary_color
        else null
      end,
      'custom_branding_enabled', coalesce(cs.custom_branding_enabled, false),
      'customer_name', c.name,
      'customer_phone', c.phone,
      'customer_address', nullif(trim(concat_ws(', ', c.address_line1, c.city)), ''),
      'sales_rep_name', emp.full_name,
      'sales_rep_phone', nullif(trim(emp.phone), ''),
      'outstanding_balance', case
        when coalesce(v_show_outstanding, false) then c.current_balance
        else null
      end,
      'collection_review', v_collection ->> 'review',
      'collection_payment_number', v_collection ->> 'payment_number',
      'collection_payment_method', v_collection ->> 'method',
      'collection_payment_amount', v_collection -> 'amount',
      'collection_discount_amount', v_collection -> 'discount_amount',
      'collection_received_at', v_collection ->> 'received_at',
      'lines', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'name', coalesce(
              nullif(trim(oi.product_name), ''),
              nullif(trim(p.name), ''),
              'Item'
            ),
            'variant_label', case
              when nullif(trim(oi.variant_label), '') is null then null
              when lower(trim(oi.variant_label)) = 'default' then null
              else trim(oi.variant_label)
            end,
            'sku', coalesce(
              nullif(trim(oi.sku), ''),
              nullif(trim(p.sku), '')
            ),
            'quantity', oi.quantity,
            'unit_price', oi.unit_price,
            'discount', oi.discount,
            'discount_type', nullif(trim(oi.discount_type), ''),
            'line_total', oi.line_total
          )
          order by oi.created_at, oi.id
        )
        from public.order_items oi
        left join public.products p on p.id = oi.product_id
        where oi.order_id = v_order.id
          and oi.company_id = v_order.company_id
      ), '[]'::jsonb)
    )
    into v_payload
    from public.companies co
    join public.company_settings cs on cs.company_id = co.id
    join public.customers c on c.id = v_order.customer_id
    left join public.employees emp on emp.id = v_order.employee_id
    where co.id = v_order.company_id;

    return v_payload;
  end if;

  if v_token.purpose in ('collection_acknowledgement', 'receipt')
     and v_token.payment_id is not null then
    select * into v_payment
    from public.payments
    where id = v_token.payment_id
      and company_id = v_token.company_id
      and deleted_at is null;

    if not found then
      return null;
    end if;

    select jsonb_build_object(
      'purpose', v_token.purpose,
      'payment_number', v_payment.payment_number,
      'amount', v_payment.amount,
      'discount_amount', coalesce(v_payment.discount_amount, 0),
      'method', v_payment.method,
      'status', v_payment.status,
      'received_at', v_payment.received_at,
      'reference', v_payment.reference,
      'notes', v_payment.notes,
      'pending_review', v_payment.status = 'pending',
      'company_name', co.name,
      'currency', coalesce(cs.currency, 'USD'),
      'currency_position', coalesce(cs.currency_position, 'before'),
      'document_logo_url', cs.document_logo_url,
      'document_show_business_name_with_logo',
        coalesce(cs.document_show_business_name_with_logo, false),
      'document_address', nullif(trim(cs.document_address), ''),
      'document_phone', nullif(trim(cs.document_phone), ''),
      'document_email', nullif(trim(cs.document_email), ''),
      'document_terms', nullif(trim(cs.document_terms), ''),
      'document_tagline', nullif(trim(cs.document_tagline), ''),
      'document_print_template', coalesce(cs.document_print_template, 'standard'),
      'document_logo_print_black', coalesce(cs.document_logo_print_black, false),
      'document_authorized_signature_url', cs.document_authorized_signature_url,
      'logo_url', case
        when coalesce(cs.custom_branding_enabled, false) then cs.logo_url
        else null
      end,
      'logo_light_url', case
        when coalesce(cs.custom_branding_enabled, false) then cs.logo_light_url
        else null
      end,
      'primary_color', case
        when coalesce(cs.custom_branding_enabled, false) then cs.primary_color
        else null
      end,
      'custom_branding_enabled', coalesce(cs.custom_branding_enabled, false),
      'customer_name', c.name,
      'customer_phone', c.phone,
      'sales_rep_name', emp.full_name,
      'sales_rep_phone', nullif(trim(emp.phone), '')
    )
    into v_payload
    from public.companies co
    join public.company_settings cs on cs.company_id = co.id
    join public.customers c on c.id = v_payment.customer_id
    left join public.employees emp on emp.id = v_payment.employee_id
    where co.id = v_payment.company_id;

    return v_payload;
  end if;

  return null;
end;
$$;

comment on function public.get_public_document_by_token(text) is
  'Anon-safe resolve for order/collection/receipt document tokens. Collection docs include discount_amount.';

revoke all on function public.get_public_document_by_token(text) from public;
grant execute on function public.get_public_document_by_token(text) to anon, authenticated;
