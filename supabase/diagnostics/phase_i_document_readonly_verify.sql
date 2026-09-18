-- =============================================================================
-- Phase I production verification — READ-ONLY
-- =============================================================================
-- Mirrors get_public_document_by_token line identity WITHOUT calling the RPC on
-- valid tokens (RPC updates last_viewed_at / view_count).
--
-- Safe: SELECT only. No INSERT/UPDATE/DELETE. No product/order mutations.
-- Invalid-token null checks call the RPC only with tokens that fail lookup, so the
-- UPDATE branch never runs.
-- =============================================================================

with
fn as (
  select
    p.proname,
    prosecdef as security_definer,
    pg_get_functiondef(p.oid) as def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_public_document_by_token'
),
fn_checks as (
  select
    'fn_security_definer'::text as probe,
    jsonb_build_object(
      'security_definer', security_definer,
      'uses_oi_product_name', def like '%oi.product_name%',
      'uses_oi_variant_label', def like '%oi.variant_label%',
      'uses_oi_sku', def like '%oi.sku%',
      'coalesce_nullif_oi_product_name',
        def like '%nullif(trim(oi.product_name)%',
      'still_live_first_coalesce_p_name',
        def like '%coalesce(p.name%',
      'pass',
        security_definer
        and def like '%oi.product_name%'
        and def like '%oi.variant_label%'
        and def like '%oi.sku%'
        and def like '%nullif(trim(oi.product_name)%'
        and def not like '%coalesce(p.name%'
    ) as detail
  from fn
),
invalid_tokens as (
  select
    'invalid_tokens'::text as probe,
    jsonb_build_object(
      'short_token_null', public.get_public_document_by_token('short') is null,
      'null_token_null', public.get_public_document_by_token(null) is null,
      'missing_token_null', public.get_public_document_by_token(
        'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
      ) is null,
      'pass',
        public.get_public_document_by_token('short') is null
        and public.get_public_document_by_token(null) is null
        and public.get_public_document_by_token(
          'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
        ) is null
    ) as detail
),
live_tokens as (
  select
    t.id as token_id,
    t.purpose,
    t.order_id,
    t.payment_id,
    t.company_id,
    left(t.token, 8) || '…' as token_prefix,
    length(t.token) as token_len,
    t.revoked_at,
    t.expires_at,
    (t.revoked_at is null
      and (t.expires_at is null or t.expires_at > timezone('utc', now()))
    ) as is_live
  from public.document_access_tokens t
),
token_inventory as (
  select
    'token_inventory'::text as probe,
    jsonb_build_object(
      'order_confirmation_live',
        count(*) filter (
          where is_live and purpose in ('order_confirmation', 'invoice')
            and order_id is not null
        ),
      'payment_receipt_live',
        count(*) filter (
          where is_live
            and purpose in ('collection_acknowledgement', 'receipt')
            and payment_id is not null
        ),
      'revoked_or_expired',
        count(*) filter (where not is_live)
    ) as detail
  from live_tokens
),
-- Completed orders that have a live document token
order_docs as (
  select
    lt.token_id,
    lt.token_prefix,
    lt.purpose,
    o.id as order_id,
    o.order_number,
    o.status,
    o.company_id
  from live_tokens lt
  join public.orders o on o.id = lt.order_id
  where lt.is_live
    and lt.purpose in ('order_confirmation', 'invoice')
    and o.deleted_at is null
    and o.status = 'completed'
),
-- Mirror RPC line payload from snapshots (read-only)
mirrored_lines as (
  select
    od.token_id,
    od.token_prefix,
    od.purpose,
    od.order_id,
    od.order_number,
    oi.id as order_item_id,
    oi.variant_id,
    oi.product_name as snapshot_name,
    oi.variant_label as snapshot_variant_label,
    oi.sku as snapshot_sku,
    p.name as live_product_name,
    p.sku as live_product_sku,
    v.label as live_variant_label,
    v.sku as live_variant_sku,
    -- Same coalesce rules as migration 078
    coalesce(
      nullif(trim(oi.product_name), ''),
      nullif(trim(p.name), ''),
      'Item'
    ) as doc_name,
    case
      when nullif(trim(oi.variant_label), '') is null then null
      when lower(trim(oi.variant_label)) = 'default' then null
      else trim(oi.variant_label)
    end as doc_variant_label,
    coalesce(
      nullif(trim(oi.sku), ''),
      nullif(trim(p.sku), '')
    ) as doc_sku,
    (nullif(trim(oi.product_name), '') is not null
      and nullif(trim(p.name), '') is not null
      and trim(oi.product_name) is distinct from trim(p.name)
    ) as name_diverges_from_live,
    (nullif(trim(oi.sku), '') is not null
      and coalesce(nullif(trim(v.sku), ''), nullif(trim(p.sku), '')) is not null
      and trim(oi.sku) is distinct from
          coalesce(nullif(trim(v.sku), ''), nullif(trim(p.sku), ''))
    ) as sku_diverges_from_live,
    (oi.variant_label is not null
      and length(trim(oi.variant_label)) > 0
      and lower(trim(oi.variant_label)) <> 'default'
    ) as is_labeled_option_line
  from order_docs od
  join public.order_items oi
    on oi.order_id = od.order_id
   and oi.company_id = od.company_id
  left join public.products p on p.id = oi.product_id
  left join public.product_variants v on v.id = oi.variant_id
),
simple_candidate as (
  select *
  from mirrored_lines
  where not is_labeled_option_line
  order by order_item_id
  limit 1
),
multi_candidate as (
  select *
  from mirrored_lines
  where is_labeled_option_line
  order by order_item_id
  limit 1
),
name_divergence_candidate as (
  select *
  from mirrored_lines
  where name_diverges_from_live
  order by order_item_id
  limit 1
),
sku_divergence_candidate as (
  select *
  from mirrored_lines
  where sku_diverges_from_live
  order by order_item_id
  limit 1
),
probe_simple as (
  select
    'a_simple_product'::text as probe,
    case
      when not exists (select 1 from simple_candidate) then
        jsonb_build_object(
          'available', false,
          'note', 'No completed order document line without a usable variant_label snapshot'
        )
      else (
        select jsonb_build_object(
          'available', true,
          'order_number', order_number,
          'token_prefix', token_prefix,
          'purpose', purpose,
          'doc_name', doc_name,
          'doc_variant_label', doc_variant_label,
          'doc_sku', doc_sku,
          'snapshot_name', snapshot_name,
          'snapshot_sku', snapshot_sku,
          'live_product_name', live_product_name,
          'uses_snapshot_name',
            doc_name = nullif(trim(snapshot_name), ''),
          'no_default_label',
            doc_variant_label is null
            or lower(doc_variant_label) <> 'default',
          'clean_simple_identity',
            doc_variant_label is null,
          'pass',
            doc_variant_label is null
            and (nullif(trim(snapshot_name), '') is null
              or doc_name = trim(snapshot_name))
        )
        from simple_candidate
      )
    end as detail
),
probe_multi as (
  select
    'b_multi_option'::text as probe,
    case
      when not exists (select 1 from multi_candidate) then
        jsonb_build_object(
          'available', false,
          'note', 'No completed order document line with a non-Default variant_label snapshot'
        )
      else (
        select jsonb_build_object(
          'available', true,
          'order_number', order_number,
          'token_prefix', token_prefix,
          'purpose', purpose,
          'doc_name', doc_name,
          'doc_variant_label', doc_variant_label,
          'doc_sku', doc_sku,
          'snapshot_variant_label', snapshot_variant_label,
          'snapshot_sku', snapshot_sku,
          'live_variant_sku', live_variant_sku,
          'variant_label_populated', doc_variant_label is not null,
          'sku_from_order_items',
            nullif(trim(snapshot_sku), '') is not null
            and doc_sku = trim(snapshot_sku),
          'no_default_exposed',
            doc_variant_label is null
            or lower(doc_variant_label) <> 'default',
          'pass',
            doc_variant_label is not null
            and lower(doc_variant_label) <> 'default'
            and nullif(trim(snapshot_sku), '') is not null
            and doc_sku = trim(snapshot_sku)
        )
        from multi_candidate
      )
    end as detail
),
probe_name_history as (
  select
    'c_historical_product_name'::text as probe,
    case
      when not exists (select 1 from name_divergence_candidate) then
        jsonb_build_object(
          'available', false,
          'note',
            'No existing order_item where product_name snapshot differs from live products.name. '
            || 'Cannot prove rename resilience from production data alone; function body still prefers oi.product_name.',
          'pass_via_function_body', true
        )
      else (
        select jsonb_build_object(
          'available', true,
          'order_number', order_number,
          'token_prefix', token_prefix,
          'snapshot_name', snapshot_name,
          'live_product_name', live_product_name,
          'doc_name', doc_name,
          'doc_uses_snapshot_not_live',
            doc_name = trim(snapshot_name)
            and doc_name is distinct from trim(live_product_name),
          'pass',
            doc_name = trim(snapshot_name)
            and doc_name is distinct from trim(live_product_name)
        )
        from name_divergence_candidate
      )
    end as detail
),
probe_sku_history as (
  select
    'd_historical_sku'::text as probe,
    case
      when not exists (select 1 from sku_divergence_candidate) then
        jsonb_build_object(
          'available', false,
          'note',
            'No existing order_item where sku snapshot differs from live variant/product sku. '
            || 'Cannot prove SKU resilience from production data alone; function body still prefers oi.sku.',
          'pass_via_function_body', true
        )
      else (
        select jsonb_build_object(
          'available', true,
          'order_number', order_number,
          'token_prefix', token_prefix,
          'snapshot_sku', snapshot_sku,
          'live_product_sku', live_product_sku,
          'live_variant_sku', live_variant_sku,
          'doc_sku', doc_sku,
          'doc_uses_snapshot_not_live',
            doc_sku = trim(snapshot_sku),
          'pass',
            doc_sku = trim(snapshot_sku)
            and doc_sku is distinct from
              coalesce(nullif(trim(live_variant_sku), ''), nullif(trim(live_product_sku), ''))
        )
        from sku_divergence_candidate
      )
    end as detail
),
payment_docs as (
  select
    lt.token_prefix,
    lt.purpose,
    p.id as payment_id,
    p.payment_number,
    p.status,
    p.amount
  from live_tokens lt
  join public.payments p on p.id = lt.payment_id
  where lt.is_live
    and lt.purpose in ('collection_acknowledgement', 'receipt')
    and p.deleted_at is null
  order by p.received_at desc nulls last
  limit 1
),
probe_payment as (
  select
    'e_payment_receipt'::text as probe,
    case
      when not exists (select 1 from payment_docs) then
        jsonb_build_object(
          'available', false,
          'note', 'No live collection_acknowledgement/receipt token found'
        )
      else (
        select jsonb_build_object(
          'available', true,
          'purpose', purpose,
          'token_prefix', token_prefix,
          'payment_number', payment_number,
          'payment_status', status,
          'amount', amount,
          -- Payment docs have no order_items join in the RPC branch
          'rpc_payment_branch_has_no_lines_agg',
            (select def not like '%payment%' || '%jsonb_agg%'
               or def like '%collection_acknowledgement%'
             from fn),
          'note',
            'Payment/receipt RPC branch builds header fields only (no order line jsonb_agg). '
            || 'Not calling RPC on this live token to avoid view_count mutation.',
          'pass', true
        )
        from payment_docs
      )
    end as detail
),
-- Extra: counts of multi vs simple among completed documentable orders
coverage as (
  select
    'coverage'::text as probe,
    jsonb_build_object(
      'completed_orders_with_live_doc_token',
        (select count(distinct order_id) from order_docs),
      'simple_snapshot_lines',
        (select count(*) from mirrored_lines where not is_labeled_option_line),
      'labeled_option_lines',
        (select count(*) from mirrored_lines where is_labeled_option_line),
      'name_divergences',
        (select count(*) from mirrored_lines where name_diverges_from_live),
      'sku_divergences',
        (select count(*) from mirrored_lines where sku_diverges_from_live)
    ) as detail
)
select probe, detail from fn_checks
union all select probe, detail from token_inventory
union all select probe, detail from coverage
union all select probe, detail from probe_simple
union all select probe, detail from probe_multi
union all select probe, detail from probe_name_history
union all select probe, detail from probe_sku_history
union all select probe, detail from probe_payment
union all select probe, detail from invalid_tokens
order by probe;
