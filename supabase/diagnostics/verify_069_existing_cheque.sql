-- Verify 069 existing-cheque tracking rules (run in SQL Editor after migrate).
-- Replace :company_id / :customer_id / session as needed — Owner/Manager session.

-- A) create_existing_cheque must leave payment_id null and balances untouched.
-- Capture customer.current_balance before/after; assert equal.

-- B) pending_approval stats must not count source=existing collected rows
--    without payment_id.

-- C) bounce_cheque on existing tracking-only must set status=bounced without
--    changing customer.current_balance / wallet_balance.

select
  c.id,
  c.source,
  c.status,
  c.payment_id,
  c.balance_applied_at,
  c.applied_ar_amount,
  c.applied_wallet_amount
from public.cheques c
where c.deleted_at is null
  and c.source = 'existing'
order by c.created_at desc
limit 20;
