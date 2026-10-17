-- =============================================================================
-- 108 — Require collections to cover listed receivables before Wallet credit
--
-- Prevents a completed payment from reducing global customer outstanding
-- without linking that payment to the opening balance/order it settles.
-- The check is deferred so receive_payment can insert payment + allocations
-- in either order inside one transaction.
-- =============================================================================

create or replace function public.validate_completed_payment_allocations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allocated numeric(14, 2) := 0;
  v_available numeric(14, 2) := 0;
  v_required numeric(14, 2) := 0;
begin
  if new.deleted_at is not null or new.status <> 'completed' then
    return new;
  end if;

  select coalesce(sum(pa.amount), 0)
    into v_allocated
  from public.payment_allocations pa
  where pa.payment_id = new.id;

  select coalesce(sum(greatest(o.total - coalesce(paid.amount, 0), 0)), 0)
    into v_available
  from public.orders o
  left join lateral (
    select coalesce(sum(pa.amount), 0) as amount
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.order_id = o.id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.id <> new.id
  ) paid on true
  where o.company_id = new.company_id
    and o.customer_id = new.customer_id
    and o.deleted_at is null
    and o.status in ('placed', 'partially_delivered', 'completed');

  select v_available + coalesce(
    sum(greatest(a.amount - coalesce(paid.amount, 0), 0)),
    0
  )
    into v_available
  from public.customer_receivable_adjustments a
  left join lateral (
    select coalesce(sum(pa.amount), 0) as amount
    from public.payment_allocations pa
    join public.payments p on p.id = pa.payment_id
    where pa.receivable_adjustment_id = a.id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.id <> new.id
  ) paid on true
  where a.company_id = new.company_id
    and a.customer_id = new.customer_id
    and a.kind = 'opening_balance'
    and a.reversed_at is null;

  v_required := least(new.amount, v_available);
  if v_required > 0.001 and v_allocated + 0.001 < v_required then
    raise exception
      'Allocate this payment across the customer''s listed orders/opening balance before saving. Only an amount above all outstanding becomes Wallet credit.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_payments_require_receivable_allocations
  on public.payments;

create constraint trigger trg_payments_require_receivable_allocations
after insert or update of status, amount, customer_id, deleted_at
on public.payments
deferrable initially deferred
for each row
execute function public.validate_completed_payment_allocations();

comment on function public.validate_completed_payment_allocations() is
  'Completed payments must allocate min(payment amount, listed receivables); only the excess may become wallet credit.';
