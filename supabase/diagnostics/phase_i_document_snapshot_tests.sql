-- Phase I verification for get_public_document_by_token snapshot lines.
-- Run against a project that has migrations 070–078 applied.
-- Prefer wrapping probes in BEGIN/ROLLBACK when mutating.

-- 0) Function present and granted
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as args,
  prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_public_document_by_token';

-- 1) Invalid the function body prefers oi.product_name / oi.sku / oi.variant_label
select pg_get_functiondef('public.get_public_document_by_token(text)'::regprocedure)
  like '%oi.product_name%' as uses_product_name_snapshot;

select pg_get_functiondef('public.get_public_document_by_token(text)'::regprocedure)
  like '%oi.variant_label%' as uses_variant_label_snapshot;

select pg_get_functiondef('public.get_public_document_by_token(text)'::regprocedure)
  like '%oi.sku%' as uses_sku_snapshot;

-- 2) Invalid token → null
select public.get_public_document_by_token('short') is null as short_token_null;
select public.get_public_document_by_token(null) is null as null_token_null;
select public.get_public_document_by_token(
  'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
) is null as missing_token_null;

-- 3–6) Manual probes (fill in known completed order / payment tokens):
-- a) simple product order token
-- b) multi-option order token → lines[].variant_label + lines[].sku
-- c) rename products.name after order → document name stays oi.product_name
-- d) change products.sku / variant sku after order → document sku stays oi.sku
-- e) payment/receipt token → no lines key required / empty lines ok
--
-- Example:
-- select public.get_public_document_by_token('<order-token>');
-- select public.get_public_document_by_token('<payment-token>');

-- Optional rolled-back identity probe (requires a real completed order id):
-- begin;
--   -- update products set name = 'RENAMED LIVE', sku = 'LIVE-SKU' where id = '<product_id>';
--   -- select get_public_document_by_token('<token>') ->> 'lines';
-- rollback;
