-- =============================================================================
-- 038 — Order confirmation documents & outbound notification ledger
--
-- Phase 1: opaque share tokens for a customer-facing order/invoice view,
-- plus an idempotent outbound event/dispatch ledger so completion retries
-- do not send duplicate confirmations.
--
-- Access is only via security-definer RPCs. Table RLS has no policies, so
-- PostgREST cannot read tokens or other companies' documents.
-- =============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Opaque document tokens (never expose order/company UUIDs in public URLs)
-- ---------------------------------------------------------------------------
create table if not exists public.document_access_tokens (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  order_id uuid not null references public.orders (id) on delete cascade,
  purpose text not null default 'order_confirmation',
  token text not null,
  created_by uuid references public.employees (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz,
  revoked_at timestamptz,
  last_viewed_at timestamptz,
  view_count integer not null default 0,

  constraint document_access_tokens_purpose_allowed check (
    purpose in ('order_confirmation')
  ),
  constraint document_access_tokens_token_not_blank check (
    length(trim(token)) >= 32
  )
);

create unique index if not exists document_access_tokens_token_uidx
  on public.document_access_tokens (token);

create unique index if not exists document_access_tokens_live_order_purpose_uidx
  on public.document_access_tokens (order_id, purpose)
  where revoked_at is null;

create index if not exists document_access_tokens_company_idx
  on public.document_access_tokens (company_id, created_at desc);

comment on table public.document_access_tokens is
  'Opaque share tokens for customer-facing order documents. No PostgREST access.';

alter table public.document_access_tokens enable row level security;
revoke all on table public.document_access_tokens from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- Idempotent outbound events (one confirmation per completed order)
-- ---------------------------------------------------------------------------
create table if not exists public.outbound_notification_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  event_type text not null,
  reference_type text not null,
  reference_id uuid not null,
  document_token_id uuid references public.document_access_tokens (id)
    on delete set null,
  created_at timestamptz not null default timezone('utc', now()),

  constraint outbound_notification_events_type_not_blank check (
    length(trim(event_type)) > 0
  ),
  constraint outbound_notification_events_ref_not_blank check (
    length(trim(reference_type)) > 0
  )
);

create unique index if not exists outbound_notification_events_unique
  on public.outbound_notification_events (event_type, reference_type, reference_id);

comment on table public.outbound_notification_events is
  'One row per business outbound event (e.g. order_confirmation). Prevents duplicate sends.';

alter table public.outbound_notification_events enable row level security;
revoke all on table public.outbound_notification_events from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- Per-recipient / per-channel dispatch rows
-- ---------------------------------------------------------------------------
create table if not exists public.outbound_notification_dispatches (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.outbound_notification_events (id)
    on delete cascade,
  channel text not null,
  recipient_kind text not null,
  recipient_key text not null,
  address text,
  status text not null default 'prepared',
  skip_reason text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),

  constraint outbound_notification_dispatches_channel_allowed check (
    channel in ('whatsapp', 'sms', 'in_app')
  ),
  constraint outbound_notification_dispatches_kind_allowed check (
    recipient_kind in ('customer', 'hub')
  ),
  constraint outbound_notification_dispatches_status_allowed check (
    status in ('prepared', 'skipped', 'failed')
  )
);

create unique index if not exists outbound_notification_dispatches_unique
  on public.outbound_notification_dispatches
    (event_id, channel, recipient_kind, recipient_key);

comment on table public.outbound_notification_dispatches is
  'Channel attempts for an outbound event. Unique per recipient+channel.';

alter table public.outbound_notification_dispatches enable row level security;
revoke all on table public.outbound_notification_dispatches from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- Prepare confirmation: issue/reuse token + return recipient snapshot
-- ---------------------------------------------------------------------------
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
    and r.code in ('owner', 'manager')
    and e.id is distinct from v_employee_id;

  select co.name into v_company_name
  from public.companies co
  where co.id = v_company_id;

  select emp.full_name into v_rep_name
  from public.employees emp
  where emp.id = v_order.employee_id;

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
    'hub_recipients', coalesce(v_hub, '[]'::jsonb)
  );
end;
$$;

comment on function public.prepare_order_confirmation(uuid) is
  'Issues or reuses an order document token and returns confirmation recipients. Authenticated company members only.';

grant execute on function public.prepare_order_confirmation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Record a channel dispatch (insert-once)
-- ---------------------------------------------------------------------------
create or replace function public.record_outbound_dispatch(
  p_event_id uuid,
  p_channel text,
  p_recipient_kind text,
  p_recipient_key text,
  p_address text default null,
  p_status text default 'prepared',
  p_skip_reason text default null,
  p_payload jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_count integer := 0;
begin
  v_company_id := public.current_company_id();
  if v_company_id is null then
    raise exception 'Session context missing.';
  end if;

  if not exists (
    select 1
    from public.outbound_notification_events e
    where e.id = p_event_id
      and e.company_id = v_company_id
  ) then
    raise exception 'Notification event not found.';
  end if;

  insert into public.outbound_notification_dispatches (
    event_id,
    channel,
    recipient_kind,
    recipient_key,
    address,
    status,
    skip_reason,
    payload
  ) values (
    p_event_id,
    p_channel,
    p_recipient_kind,
    p_recipient_key,
    nullif(trim(p_address), ''),
    p_status,
    nullif(trim(p_skip_reason), ''),
    coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (event_id, channel, recipient_kind, recipient_key) do nothing;

  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

comment on function public.record_outbound_dispatch(
  uuid, text, text, text, text, text, text, jsonb
) is
  'Inserts a dispatch row if missing. Returns true when this call created the row.';

grant execute on function public.record_outbound_dispatch(
  uuid, text, text, text, text, text, text, jsonb
) to authenticated;

-- ---------------------------------------------------------------------------
-- Public document resolve — no session, token is the capability
-- ---------------------------------------------------------------------------
create or replace function public.get_order_document_by_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token public.document_access_tokens%rowtype;
  v_order public.orders%rowtype;
  v_payload jsonb;
  v_show_outstanding boolean;
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

  select * into v_order
  from public.orders
  where id = v_token.order_id
    and company_id = v_token.company_id
    and deleted_at is null
    and status = 'completed';

  if not found then
    return null;
  end if;

  update public.document_access_tokens
  set last_viewed_at = timezone('utc', now()),
      view_count = view_count + 1
  where id = v_token.id;

  select coalesce(
    (cs.financial_visibility_policies ->> 'outstanding_balance') = 'customer_copy',
    false
  )
  into v_show_outstanding
  from public.company_settings cs
  where cs.company_id = v_order.company_id;

  select jsonb_build_object(
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
  left join public.company_settings cs on cs.company_id = co.id
  left join public.customers c on c.id = v_order.customer_id
  left join public.employees emp on emp.id = v_order.employee_id
  where co.id = v_order.company_id;

  return v_payload;
end;
$$;

comment on function public.get_order_document_by_token(text) is
  'Resolves a customer-facing order document by opaque token. Returns null when unauthorized or missing. Does not expose internal UUIDs.';

grant execute on function public.get_order_document_by_token(text)
  to anon, authenticated;
