-- =============================================================================
-- 061 — Separate document logo from Custom Branding brand assets
--
-- document_logo_url  → customer invoices / receipts / /d/<token> (all tenants)
-- logo_url / logo_light_url → Hub sidebar + Brand Assets (Custom Branding only)
-- =============================================================================

alter table public.company_settings
  add column if not exists document_logo_url text;

comment on column public.company_settings.document_logo_url is
  'Customer-facing business logo for invoices, receipts, and /d/<token> documents. '
  'Independent of Custom Branding brand assets (logo_url / logo_light_url).';

comment on column public.company_settings.logo_url is
  'Custom Branding dark-chrome / reverse wordmark (Hub sidebar, splash). '
  'Not used as the document issuer logo.';

comment on column public.company_settings.logo_light_url is
  'Custom Branding light-surface wordmark. Not used as the document issuer logo.';

-- ---------------------------------------------------------------------------
-- Data backfill
--
-- Limitation: the DB cannot tell whether an existing logo_url / logo_light_url
-- was uploaded for Custom Branding or for the pre-061 Business logo flow that
-- incorrectly wrote brand-asset columns. Strategy:
--
-- 1) Always copy the previous document-resolver preference into
--    document_logo_url: prefer logo_light_url, else logo_url.
-- 2) custom_branding_enabled = false → clear brand-asset columns (in-app
--    branding never applied them; they only polluted document/settings UI).
-- 3) custom_branding_enabled = true AND logo_url is not distinct from
--    logo_light_url → clear brand assets. That mirror pattern is exactly what
--    saveDocumentIdentity wrote (nextDark = current.logoUrl ?? nextLight when
--    dark was empty). Distinct dark/light pairs are preserved as intentional
--    Brand Assets.
-- ---------------------------------------------------------------------------

update public.company_settings
set document_logo_url = coalesce(
  nullif(trim(logo_light_url), ''),
  nullif(trim(logo_url), '')
)
where nullif(trim(document_logo_url), '') is null
  and coalesce(
    nullif(trim(logo_light_url), ''),
    nullif(trim(logo_url), '')
  ) is not null;

update public.company_settings
set
  logo_url = null,
  logo_light_url = null
where coalesce(custom_branding_enabled, false) = false
  and nullif(trim(document_logo_url), '') is not null;

update public.company_settings
set
  logo_url = null,
  logo_light_url = null
where coalesce(custom_branding_enabled, false) = true
  and nullif(trim(document_logo_url), '') is not null
  and logo_url is not distinct from logo_light_url
  and nullif(trim(logo_light_url), '') is not null;

-- ---------------------------------------------------------------------------
-- Permissions: document logo vs brand assets
-- ---------------------------------------------------------------------------

create or replace function public.can_manage_company_logo()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := public.current_role_code();
begin
  if v_role is null then
    return false;
  end if;
  return v_role in ('owner', 'administrator');
end;
$$;

comment on function public.can_manage_company_logo() is
  'Owner/administrator may update document_logo_url and document identity toggles.';

create or replace function public.can_manage_company_branding()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := public.current_role_code();
  v_company uuid := public.current_company_id();
  v_enabled boolean;
begin
  if v_role is null or v_company is null then
    return false;
  end if;

  if v_role not in ('owner', 'administrator') then
    return false;
  end if;

  select cs.custom_branding_enabled
  into v_enabled
  from public.company_settings cs
  where cs.company_id = v_company;

  return coalesce(v_enabled, false);
end;
$$;

comment on function public.can_manage_company_branding() is
  'Owner/administrator may edit brand assets and accent/nav only when '
  'custom_branding_enabled is true.';

create or replace function public.protect_company_branding()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    NEW.custom_branding_enabled := false;
    return NEW;
  end if;

  if NEW.custom_branding_enabled is distinct from OLD.custom_branding_enabled then
    raise exception 'custom_branding_enabled cannot be changed from the application'
      using errcode = '42501';
  end if;

  if NEW.document_logo_url is distinct from OLD.document_logo_url
     or NEW.document_show_business_name_with_logo
          is distinct from OLD.document_show_business_name_with_logo then
    if not public.can_manage_company_logo() then
      raise exception 'You do not have permission to update document identity settings'
        using errcode = '42501';
    end if;
  end if;

  if NEW.logo_url is distinct from OLD.logo_url
     or NEW.logo_light_url is distinct from OLD.logo_light_url
     or NEW.primary_color is distinct from OLD.primary_color
     or NEW.nav_background_color is distinct from OLD.nav_background_color then
    if not public.can_manage_company_branding() then
      raise exception 'You do not have permission to update business branding'
        using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$$;

-- Storage: document logo uploads must work without Custom Branding entitlement.
drop policy if exists "company_branding_insert_managers" on storage.objects;
create policy "company_branding_insert_managers"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and (
      public.can_manage_company_branding()
      or public.can_manage_company_logo()
    )
  );

drop policy if exists "company_branding_update_managers" on storage.objects;
create policy "company_branding_update_managers"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and (
      public.can_manage_company_branding()
      or public.can_manage_company_logo()
    )
  )
  with check (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and (
      public.can_manage_company_branding()
      or public.can_manage_company_logo()
    )
  );

drop policy if exists "company_branding_delete_managers" on storage.objects;
create policy "company_branding_delete_managers"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'company-branding'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and (
      public.can_manage_company_branding()
      or public.can_manage_company_logo()
    )
  );

-- ---------------------------------------------------------------------------
-- Public documents: document logo always; brand logos gated for accents only
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
      'currency', coalesce(cs.currency, 'USD'),
      'currency_position', coalesce(cs.currency_position, 'before'),
      'document_logo_url', cs.document_logo_url,
      'document_show_business_name_with_logo',
        coalesce(cs.document_show_business_name_with_logo, false),
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
      'currency', coalesce(cs.currency, 'USD'),
      'currency_position', coalesce(cs.currency_position, 'before'),
      'document_logo_url', cs.document_logo_url,
      'document_show_business_name_with_logo',
        coalesce(cs.document_show_business_name_with_logo, false),
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
  'Anon-safe resolve for order/collection/receipt document tokens. '
  'document_logo_url is always returned when set; brand logos and accent stay '
  'Custom Branding gated.';

grant execute on function public.get_public_document_by_token(text) to anon, authenticated;
