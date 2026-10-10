-- =============================================================================
-- 101 — Correct an issued invoice in place
--
-- Same invoice number and document link. Stock and the customer balance move
-- by the difference. A correction cannot shrink the invoice below money already
-- collected, and the customer can change only when nothing has been collected.
-- =============================================================================

create or replace function public._invoice_line_total(
  p_quantity numeric,
  p_unit_price numeric,
  p_discount numeric,
  p_discount_type text
)
returns numeric
language plpgsql
immutable
as $$
declare
  gross numeric(14, 2);
  off numeric(14, 2);
begin
  gross := round(coalesce(p_quantity, 0) * coalesce(p_unit_price, 0), 2);
  if gross < 0 then
    gross := 0;
  end if;
  if p_discount is null or p_discount <= 0 or p_discount_type is null then
    return gross;
  end if;
  if p_discount_type = 'percentage' then
    off := round(gross * p_discount / 100, 2);
  else
    off := round(p_discount, 2);
  end if;
  if off < 0 then
    off := 0;
  end if;
  if off > gross then
    off := gross;
  end if;
  return round(gross - off, 2);
end;
$$;

revoke all on function public._invoice_line_total(numeric, numeric, numeric, text) from public;

create or replace function public.correct_invoice(
  p_order_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  o public.orders%rowtype;
  item public.order_items%rowtype;
  line jsonb;
  v_line_id uuid;
  v_product_id uuid;
  v_variant_id uuid;
  v_qty numeric(14, 3);
  v_unit_price numeric(14, 2);
  v_discount numeric(14, 2);
  v_discount_type text;
  v_line_total numeric(14, 2);
  subtotal numeric(14, 2) := 0;
  discount_percent numeric(14, 2);
  discount_fixed numeric(14, 2);
  resolved_discount numeric(14, 2);
  new_total numeric(14, 2);
  collected numeric(14, 2);
  pending_amount numeric(14, 2);
  new_customer uuid;
  old_customer uuid;
  recognized numeric(14, 2);
  seen uuid[] := '{}';
  new_delivered numeric(14, 3);
  deliver_delta numeric(14, 3);
  v_name text;
  v_sku text;
  v_label text;
  product_active boolean;
  sms_sent boolean := false;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  if not public.can_correct_financials() then
    raise exception 'Only Owner or Manager can correct an invoice.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Invoice correction is missing its details.';
  end if;

  if jsonb_typeof(p_payload -> 'lines') <> 'array'
     or jsonb_array_length(p_payload -> 'lines') = 0 then
    raise exception 'Add at least one product before saving the correction.';
  end if;

  select * into o
  from public.orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if o.status = 'draft' then
    raise exception 'Save this from Edit draft. Invoice correction is for orders that have already been placed.';
  end if;

  if o.status = 'cancelled' then
    raise exception 'Cancelled invoices cannot be corrected.';
  end if;

  if o.status not in ('placed', 'partially_delivered', 'completed') then
    raise exception 'This invoice cannot be corrected.';
  end if;

  select coalesce(sum(pa.amount), 0)
    into collected
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = o.id
    and p.deleted_at is null
    and p.status = 'completed';

  select coalesce(sum(pa.amount), 0)
    into pending_amount
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.order_id = o.id
    and p.deleted_at is null
    and p.status = 'pending';

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    v_qty := (line ->> 'quantity')::numeric;
    v_unit_price := (line ->> 'unit_price')::numeric;
    v_discount := nullif(line ->> 'discount', '')::numeric;
    v_discount_type := nullif(trim(line ->> 'discount_type'), '');
    if v_qty is null or v_qty <= 0 then
      raise exception 'Each product needs a quantity greater than zero.';
    end if;
    if v_unit_price is null or v_unit_price < 0 then
      raise exception 'Each product needs a price of zero or more.';
    end if;
    if v_discount_type is not null and v_discount_type not in ('percentage', 'fixed') then
      raise exception 'A line discount must be a percentage or a fixed amount.';
    end if;
    if v_discount_type = 'percentage' and coalesce(v_discount, 0) > 100 then
      raise exception 'A percentage discount cannot be more than 100.';
    end if;
    if v_discount is null or v_discount <= 0 or v_discount_type is null then
      v_discount := null;
      v_discount_type := null;
    end if;
    subtotal := subtotal + public._invoice_line_total(v_qty, v_unit_price, v_discount, v_discount_type);
  end loop;

  discount_percent := coalesce((p_payload ->> 'discount_percent')::numeric, 0);
  discount_fixed := coalesce((p_payload ->> 'discount_fixed_amount')::numeric, 0);
  if discount_percent < 0 then
    discount_percent := 0;
  end if;
  if discount_percent > 100 then
    discount_percent := 100;
  end if;
  if discount_fixed < 0 then
    discount_fixed := 0;
  end if;

  resolved_discount := round(subtotal * discount_percent / 100, 2);
  if discount_fixed > subtotal - resolved_discount then
    discount_fixed := subtotal - resolved_discount;
  end if;
  resolved_discount := resolved_discount + discount_fixed;
  new_total := round(subtotal - resolved_discount, 2);
  if new_total <= 0 then
    raise exception 'Invoice total must be greater than zero.';
  end if;

  if new_total + 0.009 < collected + pending_amount then
    raise exception
      'This invoice already has % collected. It cannot be reduced below that until the collection is corrected.',
      trim(to_char(collected + pending_amount, 'FM999999990.00'));
  end if;

  new_customer := nullif(p_payload ->> 'customer_id', '')::uuid;
  if new_customer is null then
    raise exception 'Choose a customer for this invoice.';
  end if;

  if new_customer is distinct from o.customer_id
     and collected + pending_amount > 0 then
    raise exception
      'This invoice already has a collection. Correct or cancel that payment before changing the customer.';
  end if;

  if new_customer is distinct from o.customer_id then
    if not exists (
      select 1 from public.customers c
      where c.id = new_customer
        and c.company_id = company
        and c.deleted_at is null
        and c.is_active = true
    ) then
      raise exception 'Customer not found.';
    end if;

    old_customer := o.customer_id;
    recognized := coalesce(o.recognized_receivable_value, 0);

    update public.customers
    set
      current_balance = greatest(current_balance - recognized, 0),
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = old_customer
      and company_id = company;

    update public.orders
    set
      customer_id = new_customer,
      recognized_receivable_value = 0,
      updated_by = emp,
      updated_at = timezone('utc', now())
    where id = o.id;

    select * into o from public.orders where id = o.id for update;
  end if;

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    v_line_id := nullif(line ->> 'id', '')::uuid;
    if v_line_id is not null then
      seen := array_append(seen, v_line_id);
    end if;
  end loop;

  for item in
    select * from public.order_items
    where order_id = o.id
      and not (id = any (seen))
    for update
  loop
    if item.delivered_quantity > 0 then
      perform public.adjust_inventory(
        o.branch_id,
        item.product_id,
        item.delivered_quantity,
        'return',
        'Invoice correction',
        null,
        'order',
        o.id,
        item.variant_id
      );
    end if;
    delete from public.order_items where id = item.id;
  end loop;

  for line in
    select value from jsonb_array_elements(p_payload -> 'lines')
  loop
    v_line_id := nullif(line ->> 'id', '')::uuid;
    v_product_id := (line ->> 'product_id')::uuid;
    v_variant_id := nullif(line ->> 'variant_id', '')::uuid;
    v_qty := (line ->> 'quantity')::numeric;
    v_unit_price := round((line ->> 'unit_price')::numeric, 2);
    v_discount := nullif(line ->> 'discount', '')::numeric;
    v_discount_type := nullif(trim(line ->> 'discount_type'), '');
    if v_discount is null or v_discount <= 0 or v_discount_type is null then
      v_discount := null;
      v_discount_type := null;
    end if;
    v_line_total := public._invoice_line_total(v_qty, v_unit_price, v_discount, v_discount_type);

    if v_product_id is null then
      raise exception 'Each product on the invoice must be identified.';
    end if;

    select p.is_active
      into product_active
    from public.products p
    where p.id = v_product_id
      and p.company_id = company
      and p.deleted_at is null;

    if product_active is null then
      raise exception 'A product on this invoice is no longer available.';
    end if;

    if v_variant_id is null then
      v_variant_id := (public.resolve_default_product_variant(company, v_product_id)).id;
    end if;

    if v_line_id is null then
      if product_active is not true then
        raise exception 'That product is no longer for sale.';
      end if;

      new_delivered := case when o.status = 'completed' then v_qty else 0 end;
      if new_delivered > 0 then
        perform public.assert_order_line_stock_available(
          company, o.branch_id, v_variant_id, new_delivered
        );
        perform public.adjust_inventory(
          o.branch_id,
          v_product_id,
          -new_delivered,
          'sale',
          'Invoice correction',
          null,
          'order',
          o.id,
          v_variant_id
        );
      end if;

      insert into public.order_items (
        company_id,
        order_id,
        product_id,
        variant_id,
        quantity,
        unit_price,
        discount,
        discount_type,
        line_total,
        delivered_quantity,
        cancelled_quantity,
        created_by,
        updated_by
      ) values (
        company,
        o.id,
        v_product_id,
        v_variant_id,
        v_qty,
        v_unit_price,
        v_discount,
        v_discount_type,
        v_line_total,
        new_delivered,
        0,
        emp,
        emp
      );
    else
      select * into item
      from public.order_items
      where id = v_line_id
        and order_id = o.id
      for update;

      if not found then
        raise exception 'A product line on this invoice could not be found.';
      end if;

      if product_active is not true and item.product_id is distinct from v_product_id then
        raise exception 'That product is no longer for sale.';
      end if;

      if v_qty < item.cancelled_quantity then
        raise exception 'Quantity cannot be lower than the amount already cancelled on that line.';
      end if;

      if o.status = 'completed' then
        new_delivered := v_qty - item.cancelled_quantity;
      else
        new_delivered := least(item.delivered_quantity, v_qty - item.cancelled_quantity);
      end if;

      if item.variant_id is distinct from v_variant_id
         or item.product_id is distinct from v_product_id then
        if item.delivered_quantity > 0 then
          perform public.adjust_inventory(
            o.branch_id,
            item.product_id,
            item.delivered_quantity,
            'return',
            'Invoice correction',
            null,
            'order',
            o.id,
            item.variant_id
          );
        end if;
        if new_delivered > 0 then
          perform public.assert_order_line_stock_available(
            company, o.branch_id, v_variant_id, new_delivered
          );
          perform public.adjust_inventory(
            o.branch_id,
            v_product_id,
            -new_delivered,
            'sale',
            'Invoice correction',
            null,
            'order',
            o.id,
            variant_id
          );
        end if;
      else
        deliver_delta := new_delivered - item.delivered_quantity;
        if deliver_delta > 0 then
          perform public.assert_order_line_stock_available(
            company, o.branch_id, variant_id, deliver_delta
          );
          perform public.adjust_inventory(
            o.branch_id,
            v_product_id,
            -deliver_delta,
            'sale',
            'Invoice correction',
            null,
            'order',
            o.id,
            variant_id
          );
        elsif deliver_delta < 0 then
          perform public.adjust_inventory(
            o.branch_id,
            v_product_id,
            -deliver_delta,
            'return',
            'Invoice correction',
            null,
            'order',
            o.id,
            variant_id
          );
        end if;
      end if;

      select p.name, v.sku, nullif(trim(coalesce(v.label, '')), '')
        into v_name, v_sku, v_label
      from public.product_variants v
      join public.products p on p.id = v.product_id
      where v.id = v_variant_id
        and v.company_id = company;

      update public.order_items
      set
        product_id = v_product_id,
        variant_id = v_variant_id,
        quantity = v_qty,
        unit_price = v_unit_price,
        discount = v_discount,
        discount_type = v_discount_type,
        line_total = v_line_total,
        delivered_quantity = new_delivered,
        product_name = case
          when item.variant_id is distinct from v_variant_id
            or item.product_id is distinct from v_product_id
          then coalesce(nullif(trim(v_name), ''), product_name)
          else product_name
        end,
        sku = case
          when item.variant_id is distinct from v_variant_id
            or item.product_id is distinct from v_product_id
          then v_sku
          else sku
        end,
        variant_label = case
          when item.variant_id is distinct from v_variant_id
            or item.product_id is distinct from v_product_id
          then v_label
          else variant_label
        end,
        updated_by = emp,
        updated_at = timezone('utc', now())
      where id = item.id;
    end if;
  end loop;

  update public.orders
  set
    payment_method = case
      when collected + pending_amount > 0 then payment_method
      else coalesce(nullif(trim(p_payload ->> 'payment_method'), ''), payment_method)
    end,
    notes = nullif(trim(p_payload ->> 'notes'), ''),
    subtotal = subtotal,
    discount_percent = discount_percent,
    discount_fixed_amount = discount_fixed,
    discount_amount = resolved_discount,
    total = new_total,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.refresh_order_fulfillment_status(o.id);
  perform public.apply_order_fulfillment_receivable(o.id);
  perform public.refresh_order_payment_status(o.id);

  select exists (
    select 1
    from public.outbound_notification_events e
    join public.outbound_notification_dispatches d on d.event_id = e.id
    where e.company_id = company
      and e.event_type = 'order_confirmation'
      and e.reference_type = 'order'
      and e.reference_id = o.id
      and d.channel = 'sms'
      and d.recipient_kind = 'customer'
      and d.status = 'sent'
  )
  into sms_sent;

  perform public.log_company_activity(
    company,
    'orders',
    'invoice_corrected',
    'Invoice ' || o.order_number || ' corrected',
    emp,
    null,
    'order',
    o.id,
    jsonb_build_object(
      'order_number', o.order_number,
      'total', new_total
    )
  );

  return jsonb_build_object(
    'order_id', o.id,
    'order_number', o.order_number,
    'sms_previously_sent', sms_sent
  );
end;
$$;

comment on function public.correct_invoice(uuid, jsonb) is
  'Owner/Manager correction of a placed, partial, or completed invoice. Same number and document link. Adjusts stock and receivable by the difference.';

revoke all on function public.correct_invoice(uuid, jsonb) from public;
grant execute on function public.correct_invoice(uuid, jsonb) to authenticated;

-- A fresh event so the SMS claim is not blocked by the original confirmation.
create or replace function public.prepare_invoice_correction_sms(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  o public.orders%rowtype;
  v_token text;
  v_token_id uuid;
  v_event_id uuid;
  v_customer jsonb;
  v_company_name text;
  v_currency text;
  v_rep_name text;
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  select * into o
  from public.orders
  where id = p_order_id
    and company_id = company
    and deleted_at is null;

  if not found then
    return jsonb_build_object('send', false);
  end if;

  if not exists (
    select 1
    from public.outbound_notification_events e
    join public.outbound_notification_dispatches d on d.event_id = e.id
    where e.company_id = company
      and e.event_type = 'order_confirmation'
      and e.reference_type = 'order'
      and e.reference_id = o.id
      and d.channel = 'sms'
      and d.recipient_kind = 'customer'
      and d.status = 'sent'
  ) then
    return jsonb_build_object('send', false);
  end if;

  select t.id, t.token into v_token_id, v_token
  from public.document_access_tokens t
  where t.order_id = o.id
    and t.purpose = 'order_confirmation'
    and t.revoked_at is null
    and (t.expires_at is null or t.expires_at > timezone('utc', now()))
  limit 1;

  if v_token is null then
    return jsonb_build_object('send', false);
  end if;

  insert into public.outbound_notification_events (
    company_id,
    event_type,
    reference_type,
    reference_id,
    document_token_id
  ) values (
    company,
    'invoice_correction',
    'invoice_correction',
    gen_random_uuid(),
    v_token_id
  )
  returning id into v_event_id;

  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'phone', c.phone,
    'whatsapp', c.whatsapp
  )
  into v_customer
  from public.customers c
  where c.id = o.customer_id
    and c.company_id = company
    and c.deleted_at is null;

  select e.full_name into v_rep_name
  from public.employees e
  where e.id = o.employee_id;

  select co.name into v_company_name
  from public.companies co
  where co.id = company;

  select cs.currency into v_currency
  from public.company_settings cs
  where cs.company_id = company;

  return jsonb_build_object(
    'send', true,
    'event_id', v_event_id,
    'token', v_token,
    'order', jsonb_build_object(
      'number', o.order_number,
      'ordered_at', o.ordered_at,
      'completed_at', o.completed_at,
      'total', o.total,
      'discount_amount', o.discount_amount,
      'currency', coalesce(v_currency, 'USD'),
      'customer_name', v_customer ->> 'name',
      'sales_rep_name', v_rep_name,
      'company_name', v_company_name
    ),
    'customer', coalesce(v_customer, 'null'::jsonb)
  );
end;
$$;

comment on function public.prepare_invoice_correction_sms(uuid) is
  'Opens a new SMS event for an invoice correction when a customer SMS was already sent. Reuses the invoice link.';

revoke all on function public.prepare_invoice_correction_sms(uuid) from public;
grant execute on function public.prepare_invoice_correction_sms(uuid) to authenticated;
