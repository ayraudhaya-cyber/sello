-- Production sanity check after migration 066
-- Run in Supabase SQL Editor (service role / dashboard). Safe read-only.

-- 1) 066 functions present
select p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'approve_cheque_collection',
    'collect_cheque',
    'create_cheque',
    'deposit_cheque',
    'clear_cheque',
    'bounce_cheque',
    'cancel_cheque',
    'cheque_dashboard_stats',
    'can_manage_cheque_clearance',
    '_payment_apply_effect_amounts',
    '_sync_cheque_balance_after_payment',
    '_create_cheque_collection_payment'
  )
order by 1;

-- 2) Removed helper must NOT exist
select exists (
  select 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = '_backfill_cheque_effect_from_payment'
) as backfill_still_exists;  -- expect false

-- 3) 065 cheque table + counts intact
select
  count(*) as cheques_total,
  count(*) filter (where deleted_at is null) as cheques_active,
  count(*) filter (where status = 'awaiting_collection') as awaiting,
  count(*) filter (where status = 'collected') as collected,
  count(*) filter (where status = 'deposited') as deposited,
  count(*) filter (where status = 'cleared') as cleared,
  count(*) filter (where status = 'bounced') as bounced,
  count(*) filter (where status = 'cancelled') as cancelled,
  count(*) filter (where balance_applied_at is not null) as with_snapshot,
  count(*) filter (where payment_id is not null) as with_payment
from public.cheques;

-- 4) Cheque payments still readable
select count(*) as cheque_payments
from public.payments
where method = 'cheque'
  and deleted_at is null;
