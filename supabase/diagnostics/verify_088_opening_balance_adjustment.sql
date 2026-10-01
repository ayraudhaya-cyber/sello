-- 088 — Opening balance adjustment contract (run in SQL Editor as a Hub owner).
-- Does not mutate data unless you uncomment the sample call.

-- Expect true for owner / manager / administrator.
select public.can_record_opening_balance_adjustment();

-- Expect unique OB-YYYYMMDD-0001 style values per company per day.
-- select public.next_opening_balance_number(public.current_company_id());

-- record_opening_balance_adjustment must:
--   reject amount <= 0
--   reject inactive / other-company customers
--   reject sales_representative / sales_in_charge
--   insert customer_receivable_adjustments
--   add to customers.opening_balance and customers.current_balance
--   leave orders untouched
--   log company_activity_events (opening_balance_added)
