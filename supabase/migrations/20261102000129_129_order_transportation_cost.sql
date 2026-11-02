-- Order transportation cost: seller-paid (default, invoice only) or
-- receiver-paid (adds to orders.total / outstanding / AR). No SMS line.

alter table public.orders
  add column if not exists transportation_cost numeric(14, 2) not null default 0;

alter table public.orders
  add column if not exists transportation_payer text not null default 'seller';

alter table public.orders
  drop constraint if exists orders_transportation_cost_non_negative;

alter table public.orders
  add constraint orders_transportation_cost_non_negative
  check (transportation_cost >= 0);

alter table public.orders
  drop constraint if exists orders_transportation_payer_allowed;

alter table public.orders
  add constraint orders_transportation_payer_allowed
  check (transportation_payer in ('seller', 'receiver'));

comment on column public.orders.transportation_cost is
  'Delivery / transport amount shown on the invoice. Separate from discounts.';

comment on column public.orders.transportation_payer is
  'seller = shown on invoice only, not owed by the customer. '
  'receiver = included in orders.total and what they owe.';

-- Goods total = subtotal − discount + tax (transport never lives in subtotal).
create or replace function public.order_goods_total(p_order public.orders)
returns numeric
language sql
immutable
as $$
  select greatest(
    round(
      coalesce(p_order.subtotal, 0)
      - coalesce(p_order.discount_amount, 0)
      + coalesce(p_order.tax_amount, 0),
      2
    ),
    0
  )::numeric(14, 2);
$$;

revoke all on function public.order_goods_total(public.orders) from public;

create or replace function public.set_order_transportation(
  p_order_id uuid,
  p_amount numeric,
  p_payer text default 'seller'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders%rowtype;
  emp uuid := public.current_employee_id();
  company uuid := public.current_company_id();
  amount numeric(14, 2);
  payer text;
  goods numeric(14, 2);
  new_total numeric(14, 2);
begin
  if emp is null or company is null then
    raise exception 'Session context missing.';
  end if;

  amount := round(coalesce(p_amount, 0), 2);
  if amount < 0 then
    raise exception 'Transportation cannot be negative.';
  end if;

  payer := coalesce(nullif(trim(p_payer), ''), 'seller');
  if payer not in ('seller', 'receiver') then
    raise exception 'Choose who pays for transportation.';
  end if;
  if amount <= 0.001 then
    amount := 0;
    payer := 'seller';
  end if;

  select * into o
  from public.orders
  where id = p_order_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  if o.company_id is distinct from company then
    raise exception 'Forbidden.';
  end if;

  if o.status not in ('placed', 'partially_delivered', 'completed') then
    raise exception 'Transportation can be set after the order is placed.';
  end if;

  goods := public.order_goods_total(o);
  if payer = 'receiver' then
    new_total := round(goods + amount, 2);
  else
    new_total := goods;
  end if;

  if new_total <= 0.001 then
    raise exception 'Order total must be greater than zero.';
  end if;

  update public.orders
  set
    transportation_cost = amount,
    transportation_payer = payer,
    total = new_total,
    updated_by = emp,
    updated_at = timezone('utc', now())
  where id = o.id;

  perform public.apply_order_fulfillment_receivable(o.id);
  perform public.refresh_order_payment_status(o.id);
end;
$$;

comment on function public.set_order_transportation(uuid, numeric, text) is
  'Sets transportation on a placed order. Receiver-paid increases total and AR; seller-paid is invoice-only.';

revoke all on function public.set_order_transportation(uuid, numeric, text) from public;
grant execute on function public.set_order_transportation(uuid, numeric, text) to authenticated;

-- Keep transport when invoice lines are corrected.
do $migration$
declare
  def text;
  updated text;
  marker constant text := 'new_total := round(v_subtotal - resolved_discount, 2);';
  injection constant text :=
    'new_total := round(v_subtotal - resolved_discount, 2);'
    || E'\n'
    || '  if coalesce(o.transportation_payer, ''seller'') = ''receiver'''
    || E'\n'
    || '     and coalesce(o.transportation_cost, 0) > 0.001 then'
    || E'\n'
    || '    new_total := round(new_total + o.transportation_cost, 2);'
    || E'\n'
    || '  end if;';
begin
  select pg_get_functiondef(
    'public.correct_invoice(uuid,jsonb)'::regprocedure
  )
  into def;

  if def is null then
    raise exception 'correct_invoice not found.';
  end if;

  if position('transportation_cost' in def) > 0
     and position('transportation_payer' in def) > 0 then
    return;
  end if;

  if position(marker in def) = 0 then
    raise exception 'Could not keep transportation on invoice correction.';
  end if;

  updated := replace(def, marker, injection);
  if updated = def then
    raise exception 'Could not keep transportation on invoice correction.';
  end if;

  execute updated;
end;
$migration$;

-- Public invoice / order document payload.
do $migration$
declare
  def text;
  updated text;
  needle text;
  replacement text;
begin
  select pg_get_functiondef(
    'public.get_public_document_by_token(text)'::regprocedure
  )
  into def;

  if def is null then
    raise exception 'get_public_document_by_token not found.';
  end if;

  if position('transportation_cost' in def) > 0 then
    return;
  end if;

  needle := '''tax_amount'', v_order.tax_amount,';
  if position(needle in def) = 0 then
    raise exception 'Could not add transportation to the public invoice document.';
  end if;

  replacement :=
    '''tax_amount'', v_order.tax_amount,'
    || E'\n'
    || '      ''transportation_cost'', coalesce(v_order.transportation_cost, 0),'
    || E'\n'
    || '      ''transportation_payer'', coalesce(v_order.transportation_payer, ''seller''),';

  updated := replace(def, needle, replacement);
  if updated = def then
    raise exception 'Could not add transportation to the public invoice document.';
  end if;

  execute updated;
end;
$migration$;
