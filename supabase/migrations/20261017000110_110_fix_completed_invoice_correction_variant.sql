-- Fix completed invoice corrections failing with:
--   column "variant_id" does not exist
--
-- Migration 102 correctly stores the selected variant in v_variant_id, but
-- four inventory-adjustment calls used the unqualified name variant_id.
-- Placed orders skipped those calls because nothing had been delivered;
-- completed orders reached them and failed.
--
-- Keep this forward-only because migration 102 may already be applied.

do $migration$
declare
  original_definition text;
  fixed_definition text;
begin
  select pg_get_functiondef(
    'public.correct_invoice(uuid,jsonb)'::regprocedure
  )
  into original_definition;

  fixed_definition := regexp_replace(
    original_definition,
    '(company,\s*o\.branch_id,\s*)variant_id(\s*,\s*deliver_delta)',
    '\1v_variant_id\2',
    'g'
  );

  fixed_definition := regexp_replace(
    fixed_definition,
    '(''order'',\s*o\.id,\s*)variant_id(\s*\))',
    '\1v_variant_id\2',
    'g'
  );

  if fixed_definition = original_definition then
    raise exception
      'correct_invoice hotfix could not find the invalid variant references';
  end if;

  if fixed_definition ~
    '(company,\s*o\.branch_id,\s*)variant_id(\s*,\s*deliver_delta)'
    or fixed_definition ~
      '(''order'',\s*o\.id,\s*)variant_id(\s*\))'
  then
    raise exception
      'correct_invoice hotfix left an invalid variant reference behind';
  end if;

  execute fixed_definition;
end;
$migration$;

comment on function public.correct_invoice(uuid, jsonb) is
  'Owner/Manager correction of a placed, partial, or completed invoice. '
  'Adjusts inventory by the selected product variant and refreshes the '
  'receivable while preserving the invoice number and document link.';
