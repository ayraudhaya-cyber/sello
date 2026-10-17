-- One-off Namson Lanka cleanup.
--
-- Business confirmation received: this tenant has never issued or consumed
-- customer wallet credit. Migration 106 prevents new duplication, but old
-- payments predate the applied-wallet snapshots needed for automatic repair.
--
-- Safety:
--   * requires exactly one company with "namson" and "lanka" in its name
--   * aborts if any completed wallet payment/order exists
--   * writes one company_activity_events audit row per changed customer
--   * changes wallet_balance only; outstanding is not guessed or rewritten

do $$
declare
  v_company_id uuid;
  v_company_name text;
  v_matches integer;
  v_customer record;
  v_repaired integer := 0;
begin
  select count(*)
    into v_matches
  from public.companies
  where lower(name) like '%namson%'
    and lower(name) like '%lanka%';

  if v_matches <> 1 then
    raise exception
      'Expected exactly one Namson Lanka company, found %.',
      v_matches;
  end if;

  select id, name
    into v_company_id, v_company_name
  from public.companies
  where lower(name) like '%namson%'
    and lower(name) like '%lanka%'
  limit 1;

  if exists (
    select 1
    from public.payments p
    where p.company_id = v_company_id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.method = 'wallet'
  ) or exists (
    select 1
    from public.orders o
    where o.company_id = v_company_id
      and o.deleted_at is null
      and o.payment_method = 'wallet'
      and o.status in ('placed', 'partially_delivered', 'completed')
  ) then
    raise exception
      'Cleanup stopped: Namson Lanka has wallet payment history. Review the ledger manually.';
  end if;

  for v_customer in
    select c.id, c.name, c.wallet_balance, c.current_balance
    from public.customers c
    where c.company_id = v_company_id
      and c.deleted_at is null
      and c.wallet_balance > 0
    order by c.name
  loop
    perform public.log_company_activity(
      v_company_id,
      'customers',
      'wallet_balance_historical_repair',
      'Removed incorrect historical wallet credit of Rs '
        || to_char(v_customer.wallet_balance, 'FM999999999990.00')
        || ' from ' || v_customer.name,
      null,
      'Sello maintenance',
      'customer',
      v_customer.id,
      jsonb_build_object(
        'wallet_before', v_customer.wallet_balance,
        'wallet_after', 0,
        'outstanding_unchanged', v_customer.current_balance,
        'reason', 'Legacy unallocated collection wallet duplication'
      )
    );

    update public.customers
    set
      wallet_balance = 0,
      updated_at = timezone('utc', now())
    where id = v_customer.id
      and company_id = v_company_id;

    v_repaired := v_repaired + 1;
  end loop;

  -- Namson confirmed there was no legitimate wallet credit. Align any
  -- snapshot rows so a later payment correction cannot restore removed credit.
  update public.payments
  set applied_wallet_amount = 0
  where company_id = v_company_id
    and deleted_at is null
    and method <> 'wallet'
    and applied_wallet_amount > 0;

  raise notice
    'Cleared incorrect wallet balances for % customer(s) in %.',
    v_repaired,
    v_company_name;
end $$;

select
  c.name,
  c.current_balance as outstanding_balance,
  c.wallet_balance
from public.customers c
join public.companies co on co.id = c.company_id
where lower(co.name) like '%namson%'
  and lower(co.name) like '%lanka%'
  and c.deleted_at is null
order by c.name;
