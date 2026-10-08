-- 098 — Compact invoice sales-rep number and authorized signature.
--
-- Compact print shows the sales rep phone from employees.phone.
-- document_authorized_signature_url is an optional image printed above
-- Authorized by. The stored file is not recolored.

alter table public.company_settings
  add column if not exists document_authorized_signature_url text;

comment on column public.company_settings.document_authorized_signature_url is
  'Optional signature image printed on compact invoices above Authorized by.';

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

    -- Pending collection wins; otherwise the latest approved collection.
    -- Displayed date is created_at (when the collector recorded it), never
    -- reviewed_at (when Owner/Manager approved).
    select jsonb_build_object(
      'review', case
        when p.status = 'pending' then 'processing'
        else 'approved'
      end,
      'payment_number', p.payment_number,
      'method', p.method,
      'amount', pa.amount,
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
  'Anon-safe resolve for order/collection/receipt document tokens. '
  'Order lines prefer order_items.product_name / variant_label / sku snapshots; '
  'live products are a null-safe legacy fallback only. '
  'Includes document issuer logo, contact block, terms, tagline, and print template. '
  'Invoice tokens include collection_review (processing/approved) for '
  'Sales collections that require Owner/Manager approval. '
  'Order tokens resolve for placed, partially delivered, and completed sales. '
  'Invoice collection_received_at is payments.created_at (recorded), '
  'not reviewed_at (approved).';

grant execute on function public.get_public_document_by_token(text) to anon, authenticated;
