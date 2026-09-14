-- Migration 067: Drop obsolete cheque backfill helper
--
-- Production applied an earlier draft of 066 that created
-- public._backfill_cheque_effect_from_payment(uuid). The current 066 source no
-- longer defines or calls it; CREATE OR REPLACE / omitting the body does not
-- remove an existing PostgreSQL function. Drop it explicitly here.
--
-- Safe: no remaining callers in 065/066 or app code.

drop function if exists public._backfill_cheque_effect_from_payment(uuid);
