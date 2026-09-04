-- =============================================================================
-- 063 — Invoice / receipt contact block + terms
--
-- Tenant-editable fields on company_settings for customer-facing documents:
--   document_address, document_phone, document_email, document_terms
-- Same permission gate as document logo (can_manage_company_logo).
-- =============================================================================

alter table public.company_settings
  add column if not exists document_address text,
  add column if not exists document_phone text,
  add column if not exists document_email text,
  add column if not exists document_terms text;

comment on column public.company_settings.document_address is
  'Business address shown on customer invoices and receipts.';
comment on column public.company_settings.document_phone is
  'Business contact phone shown on customer invoices and receipts.';
comment on column public.company_settings.document_email is
  'Business email shown on customer invoices and receipts.';
comment on column public.company_settings.document_terms is
  'Optional terms / footer text on customer invoices and receipts.';

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
          is distinct from OLD.document_show_business_name_with_logo
     or NEW.document_address is distinct from OLD.document_address
     or NEW.document_phone is distinct from OLD.document_phone
     or NEW.document_email is distinct from OLD.document_email
     or NEW.document_terms is distinct from OLD.document_terms then
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

-- ---------------------------------------------------------------------------
-- Public documents: include issuer contact + terms
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
      'document_address', nullif(trim(cs.document_address), ''),
      'document_phone', nullif(trim(cs.document_phone), ''),
      'document_email', nullif(trim(cs.document_email), ''),
      'document_terms', nullif(trim(cs.document_terms), ''),
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
      'document_address', nullif(trim(cs.document_address), ''),
      'document_phone', nullif(trim(cs.document_phone), ''),
      'document_email', nullif(trim(cs.document_email), ''),
      'document_terms', nullif(trim(cs.document_terms), ''),
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
  'Includes document issuer logo, contact block, and terms when set.';

grant execute on function public.get_public_document_by_token(text) to anon, authenticated;
