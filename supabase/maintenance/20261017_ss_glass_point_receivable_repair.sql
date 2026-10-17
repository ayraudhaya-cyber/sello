-- One-off SS GLASS POINT receivable repair.
--
-- Confirmed business facts:
--   * opening balance before Sello: Rs 216,600
--   * PAY rows Rs 76,000 + 102,600 + 38,000 are genuine cash collections
--   * SO-20261009-0001 for Rs 332,808 is a genuine Sello order
--
-- Expected result:
--   opening balance: Rs 216,600, fully collected
--   wallet: Rs 0
--   outstanding: Rs 332,808 (the unpaid Sello order)

do $$
declare
  v_company_id uuid;
  v_customer_id uuid;
  v_old_adjustment public.customer_receivable_adjustments%rowtype;
  v_new_adjustment_id uuid;
  v_actor_id uuid;
  v_payment_count integer;
  v_payment_total numeric(14, 2);
begin
  select c.company_id, c.id
    into v_company_id, v_customer_id
  from public.customers c
  join public.companies co on co.id = c.company_id
  where lower(co.name) like '%namson%'
    and lower(co.name) like '%lanka%'
    and lower(c.name) = 'ss glass point'
    and c.deleted_at is null;

  if v_customer_id is null then
    raise exception 'SS GLASS POINT was not found for Namson Lanka.';
  end if;

  select * into v_old_adjustment
  from public.customer_receivable_adjustments a
  where a.company_id = v_company_id
    and a.customer_id = v_customer_id
    and a.kind = 'opening_balance'
    and a.reversed_at is null;

  if not found or v_old_adjustment.amount <> 332808 then
    raise exception
      'Expected one active Rs 332,808 opening balance. No changes were made.';
  end if;

  select
    count(*),
    coalesce(sum(p.amount), 0)
  into v_payment_count, v_payment_total
  from public.payments p
  where p.company_id = v_company_id
    and p.customer_id = v_customer_id
    and p.deleted_at is null
    and p.status = 'completed'
    and p.method = 'cash'
    and p.amount in (76000, 102600, 38000)
    and not exists (
      select 1
      from public.payment_allocations pa
      where pa.payment_id = p.id
    );

  if v_payment_count <> 3 or v_payment_total <> 216600 then
    raise exception
      'Expected the three confirmed unallocated cash collections totalling Rs 216,600. No changes were made.';
  end if;

  select coalesce(p.employee_id, p.created_by)
    into v_actor_id
  from public.payments p
  where p.company_id = v_company_id
    and p.customer_id = v_customer_id
    and p.deleted_at is null
    and p.status = 'completed'
    and p.method = 'cash'
    and p.amount in (76000, 102600, 38000)
  limit 1;

  if not exists (
    select 1
    from public.orders o
    where o.company_id = v_company_id
      and o.customer_id = v_customer_id
      and o.order_number = 'SO-20261009-0001'
      and o.total = 332808
      and o.deleted_at is null
      and o.status = 'completed'
  ) then
    raise exception
      'Expected completed order SO-20261009-0001 for Rs 332,808. No changes were made.';
  end if;

  if not exists (
    select 1
    from public.customers c
    where c.id = v_customer_id
      and c.opening_balance = 332808
      and c.current_balance = 449016
      and c.wallet_balance = 0
  ) then
    raise exception
      'Customer balances changed since diagnosis. No changes were made.';
  end if;

  v_actor_id := coalesce(v_actor_id, v_old_adjustment.created_by);

  update public.customer_receivable_adjustments
  set
    reversed_at = timezone('utc', now()),
    reversed_by = v_actor_id,
    notes = concat_ws(
      E'\n',
      nullif(trim(coalesce(notes, '')), ''),
      'Corrected by verified ledger repair: amount belonged to the Sello order.'
    )
  where id = v_old_adjustment.id;

  insert into public.customer_receivable_adjustments (
    company_id,
    customer_id,
    branch_id,
    adjustment_number,
    kind,
    amount,
    recognized_at,
    notes,
    created_by,
    corrects_adjustment_id
  )
  values (
    v_company_id,
    v_customer_id,
    v_old_adjustment.branch_id,
    'OB-REPAIR-20261017-SSGP',
    'opening_balance',
    216600,
    v_old_adjustment.recognized_at,
    'Verified opening balance before Sello.',
    v_actor_id,
    v_old_adjustment.id
  )
  returning id into v_new_adjustment_id;

  insert into public.payment_allocations (
    company_id,
    payment_id,
    order_id,
    receivable_adjustment_id,
    amount,
    created_by,
    updated_by
  )
  select
    p.company_id,
    p.id,
    null,
    v_new_adjustment_id,
    p.amount,
    coalesce(p.created_by, v_actor_id),
    coalesce(p.updated_by, v_actor_id)
  from public.payments p
  where p.company_id = v_company_id
    and p.customer_id = v_customer_id
    and p.deleted_at is null
    and p.status = 'completed'
    and p.method = 'cash'
    and p.amount in (76000, 102600, 38000)
    and not exists (
      select 1
      from public.payment_allocations pa
      where pa.payment_id = p.id
    );

  update public.payments
  set
    applied_ar_amount = amount,
    applied_wallet_amount = 0
  where company_id = v_company_id
    and customer_id = v_customer_id
    and deleted_at is null
    and status = 'completed'
    and method = 'cash'
    and amount in (76000, 102600, 38000);

  update public.customers
  set
    opening_balance = 216600,
    current_balance = 332808,
    wallet_balance = 0,
    updated_at = timezone('utc', now())
  where id = v_customer_id
    and company_id = v_company_id;

  perform public.log_company_activity(
    v_company_id,
    'customers',
    'receivable_ledger_repaired',
    'SS GLASS POINT opening balance and collection allocations repaired',
    v_actor_id,
    'Sello verified repair',
    'customer',
    v_customer_id,
    jsonb_build_object(
      'opening_before', 332808,
      'opening_after', 216600,
      'collections_allocated', 216600,
      'outstanding_after', 332808,
      'wallet_after', 0,
      'replaced_adjustment_id', v_old_adjustment.id,
      'new_adjustment_id', v_new_adjustment_id
    )
  );
end $$;

select
  c.name,
  c.opening_balance,
  c.current_balance as outstanding_balance,
  c.wallet_balance
from public.customers c
join public.companies co on co.id = c.company_id
where lower(co.name) like '%namson%'
  and lower(co.name) like '%lanka%'
  and lower(c.name) = 'ss glass point';
