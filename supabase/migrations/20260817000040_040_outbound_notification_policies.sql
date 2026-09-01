-- =============================================================================
-- 040 — Configurable outbound notifications (SMS / WhatsApp + document links)
--
-- Tenant policy on company_settings.outbound_notification_policies (jsonb).
-- Expands document purposes and recipient kinds for collection acknowledgements.
-- Share intents remain device prefill (no Business API yet).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Company outbound policy (defaults preserve Phase 1 behaviour)
-- ---------------------------------------------------------------------------

alter table public.company_settings
  add column if not exists outbound_notification_policies jsonb
    not null default '{
      "channels": {"whatsapp": true, "sms": true},
      "types": {
        "order_confirmation": {
          "enabled": true,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["customer", "hub"]
        },
        "collection_acknowledgement": {
          "enabled": true,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["hub"]
        },
        "invoice": {
          "enabled": false,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["customer"]
        },
        "receipt": {
          "enabled": false,
          "whatsapp": true,
          "sms": true,
          "include_document_link": true,
          "recipients": ["customer"]
        }
      },
      "templates": {}
    }'::jsonb;

comment on column public.company_settings.outbound_notification_policies is
  'Tenant outbound messaging: channels, per-type recipients, document links, optional templates.';

-- ---------------------------------------------------------------------------
-- Document tokens: more purposes + optional payment reference
-- ---------------------------------------------------------------------------

alter table public.document_access_tokens
  alter column order_id drop not null;

alter table public.document_access_tokens
  add column if not exists payment_id uuid
    references public.payments (id) on delete cascade;

alter table public.document_access_tokens
  drop constraint if exists document_access_tokens_purpose_allowed;

alter table public.document_access_tokens
  add constraint document_access_tokens_purpose_allowed check (
    purpose in (
      'order_confirmation',
      'invoice',
      'collection_acknowledgement',
      'receipt'
    )
  );

alter table public.document_access_tokens
  drop constraint if exists document_access_tokens_reference_present;

alter table public.document_access_tokens
  add constraint document_access_tokens_reference_present check (
    order_id is not null or payment_id is not null
  );

drop index if exists document_access_tokens_live_order_purpose_uidx;

create unique index if not exists document_access_tokens_live_order_purpose_uidx
  on public.document_access_tokens (order_id, purpose)
  where revoked_at is null and order_id is not null;

create unique index if not exists document_access_tokens_live_payment_purpose_uidx
  on public.document_access_tokens (payment_id, purpose)
  where revoked_at is null and payment_id is not null;

-- ---------------------------------------------------------------------------
-- Dispatch recipient kinds: sales_rep
-- ---------------------------------------------------------------------------

alter table public.outbound_notification_dispatches
  drop constraint if exists outbound_notification_dispatches_kind_allowed;

alter table public.outbound_notification_dispatches
  add constraint outbound_notification_dispatches_kind_allowed check (
    recipient_kind in ('customer', 'hub', 'sales_rep')
  );

-- ---------------------------------------------------------------------------
-- Prepare collection acknowledgement (pending review document + recipients)
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

  if v_payment.status is distinct from 'pending' then
    raise exception 'Collection acknowledgement is only for pending review collections.';
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
    and r.code in ('owner', 'manager', 'administrator')
    and e.id is distinct from v_employee_id;

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
  'Issues a pending-collection acknowledgement token and hub recipient snapshot. Does not change balances.';

grant execute on function public.prepare_collection_acknowledgement(uuid) to authenticated;

-- Include sales rep contact on order confirmation prepare (recipient matrix).
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

  if v_order.status is distinct from 'completed' then
    raise exception 'Order confirmation is only available for completed orders.';
  end if;

  select t.id, t.token into v_token_id, v_token
  from public.document_access_tokens t
  where t.order_id = v_order.id
    and t.purpose = 'order_confirmation'
    and t.revoked_at is null
    and (t.expires_at is null or t.expires_at > timezone('utc', now()))
  limit 1;

  if v_token is null then
    v_token := encode(gen_random_bytes(24), 'hex');
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

-- ---------------------------------------------------------------------------
-- Public document resolve — order OR collection acknowledgement
-- ---------------------------------------------------------------------------

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
  v_payload jsonb;
begin
  if p_token is null or length(trim(p_token)) < 32 then
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
      and status = 'completed';

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
      'company_legal_name', co.legal_name,
      'currency', coalesce(cs.currency, 'USD'),
      'currency_position', coalesce(cs.currency_position, 'before'),
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
      'outstanding_balance', case
        when coalesce(v_show_outstanding, false) then c.current_balance
        else null
      end,
      'lines', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'name', coalesce(p.name, 'Item'),
            'sku', p.sku,
            'quantity', oi.quantity,
            'unit_price', oi.unit_price,
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
      'method', v_payment.method,
      'status', v_payment.status,
      'received_at', v_payment.received_at,
      'reference', v_payment.reference,
      'notes', v_payment.notes,
      'pending_review', v_payment.status = 'pending',
      'company_name', co.name,
      'company_legal_name', co.legal_name,
      'currency', coalesce(cs.currency, 'USD'),
      'currency_position', coalesce(cs.currency_position, 'before'),
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
      'sales_rep_name', emp.full_name
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
  'Anon-safe resolve for order/collection/receipt document tokens.';

grant execute on function public.get_public_document_by_token(text) to anon, authenticated;

-- Keep legacy order RPC as a thin wrapper for older clients.
create or replace function public.get_order_document_by_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc jsonb;
begin
  v_doc := public.get_public_document_by_token(p_token);
  if v_doc is null then
    return null;
  end if;
  if (v_doc ->> 'purpose') not in ('order_confirmation', 'invoice') then
    return null;
  end if;
  return v_doc;
end;
$$;
