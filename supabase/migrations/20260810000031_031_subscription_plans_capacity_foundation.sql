-- =============================================================================
-- Migration 031 — Scalable plans, versioned pricing, capacity & entitlements
--
-- Extends migration 005 (company-level plan/status columns) with:
--   • subscription_plans          — configurable plan catalog
--   • subscription_plan_prices    — versioned monthly/annual prices
--   • company_subscriptions       — per-business subscription + price snapshot
--   • helpers for usage / capacity / entitlements (server-ready seams)
--
-- V1 principles:
--   • Professional remains effectively unlimited (no artificial product lock)
--   • Prices live in data — never hardcode in the app
--   • Historical subscriptions keep the unit_amount snapshot when prices change
--   • Capacity checks are advisory for now; enforce in RPCs/triggers later
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Plan catalog
-- ---------------------------------------------------------------------------

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  display_order integer not null default 100,
  -- Capacity map. Missing key or JSON null = unlimited.
  -- Known keys: max_users, max_sales_representatives, max_branches, max_storage_mb
  limits jsonb not null default '{}'::jsonb,
  -- Feature entitlements. Missing key defaults to false in resolvers;
  -- Professional/Enterprise seeds set commercial features true for V1.
  entitlements jsonb not null default '{}'::jsonb,
  definition_version integer not null default 1,
  effective_from timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint subscription_plans_code_key unique (code),
  constraint subscription_plans_code_format check (code ~ '^[a-z][a-z0-9_]*$'),
  constraint subscription_plans_definition_version_positive
    check (definition_version > 0)
);

create index if not exists subscription_plans_active_idx
  on public.subscription_plans (display_order, code)
  where is_active = true;

comment on table public.subscription_plans is
  'Sello commercial plan catalog — limits and entitlements are data-driven.';

comment on column public.subscription_plans.limits is
  'JSON capacity map. null values mean unlimited. Add keys without schema changes.';

comment on column public.subscription_plans.entitlements is
  'JSON feature flags for the plan. Resolve via helpers — never hardcode in UI.';

-- ---------------------------------------------------------------------------
-- Versioned pricing (separate from plan identity)
-- ---------------------------------------------------------------------------

create table if not exists public.subscription_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.subscription_plans (id) on delete cascade,
  billing_interval text not null,
  currency text not null default 'USD',
  -- null amount = custom / contact-sales pricing (enterprise)
  amount numeric(12, 2),
  is_active boolean not null default true,
  price_version integer not null default 1,
  effective_from timestamptz not null default timezone('utc', now()),
  effective_until timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint subscription_plan_prices_interval_check
    check (billing_interval in ('month', 'year')),
  constraint subscription_plan_prices_currency_format
    check (currency ~ '^[A-Z]{3}$'),
  constraint subscription_plan_prices_amount_non_negative
    check (amount is null or amount >= 0),
  constraint subscription_plan_prices_version_positive
    check (price_version > 0),
  constraint subscription_plan_prices_effective_window
    check (effective_until is null or effective_until > effective_from)
);

create index if not exists subscription_plan_prices_plan_idx
  on public.subscription_plan_prices (plan_id, billing_interval, currency)
  where is_active = true;

comment on table public.subscription_plan_prices is
  'Versioned plan prices. Updating amount for a new version does not rewrite '
  'historical company_subscriptions.unit_amount snapshots.';

-- ---------------------------------------------------------------------------
-- Per-company subscription (commercial entitlement record)
-- ---------------------------------------------------------------------------

create table if not exists public.company_subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  plan_id uuid not null references public.subscription_plans (id),
  plan_code text not null,
  status text not null default 'active',
  billing_interval text not null default 'month',
  currency text not null default 'USD',
  -- Snapshot of the price at activation / renewal — immutable for history.
  unit_amount numeric(12, 2),
  plan_price_id uuid references public.subscription_plan_prices (id),
  trial_ends_at timestamptz,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  cancelled_at timestamptz,
  activated_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz,
  -- Optional account-level capacity overrides (add-ons / custom deals).
  -- Merged over plan.limits when resolving capacity (override wins).
  capacity_overrides jsonb not null default '{}'::jsonb,
  -- Optional entitlement overrides for custom deals.
  entitlement_overrides jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint company_subscriptions_status_check
    check (status in (
      'active', 'trialing', 'past_due', 'grace', 'suspended', 'cancelled'
    )),
  constraint company_subscriptions_interval_check
    check (billing_interval in ('month', 'year')),
  constraint company_subscriptions_currency_format
    check (currency ~ '^[A-Z]{3}$'),
  constraint company_subscriptions_expiry_check
    check (expires_at is null or expires_at >= activated_at)
);

create index if not exists company_subscriptions_company_idx
  on public.company_subscriptions (company_id, created_at desc);

create index if not exists company_subscriptions_active_idx
  on public.company_subscriptions (company_id)
  where status in ('active', 'trialing', 'past_due', 'grace');

comment on table public.company_subscriptions is
  'Business subscription records. unit_amount is a price snapshot for billing history.';

comment on column public.company_subscriptions.unit_amount is
  'Price locked at subscription start/renewal. Survives later plan_price updates.';

comment on column public.company_subscriptions.capacity_overrides is
  'Per-account limit overrides (add-ons). Merge over plan.limits — do not fork plans.';

-- Keep companies.plan codes aligned with the catalog (drop hardcoded enum).
alter table public.companies
  drop constraint if exists companies_plan_check;

-- Seed catalog before FK.
insert into public.subscription_plans (
  code, name, description, display_order, limits, entitlements, definition_version
) values
(
  'trial',
  'Trial',
  'Time-limited evaluation. Capacity mirrors Professional during V1.',
  10,
  '{}'::jsonb,
  '{
    "reports": true,
    "intelligence": true,
    "advanced_analytics": true,
    "multiple_branches": true,
    "advanced_permissions": true,
    "integrations": false,
    "api_access": false,
    "automation": false,
    "additional_storage": false
  }'::jsonb,
  1
),
(
  'starter',
  'Starter',
  'For very small teams getting started with Sello.',
  20,
  '{
    "max_users": 5,
    "max_sales_representatives": 3,
    "max_branches": 2,
    "max_storage_mb": 2048
  }'::jsonb,
  '{
    "reports": true,
    "intelligence": false,
    "advanced_analytics": false,
    "multiple_branches": true,
    "advanced_permissions": false,
    "integrations": false,
    "api_access": false,
    "automation": false,
    "additional_storage": false
  }'::jsonb,
  1
),
(
  'professional',
  'Professional',
  'Default Sello plan. Unlimited capacity in V1 — commercial tiers refine later.',
  30,
  '{}'::jsonb,
  '{
    "reports": true,
    "intelligence": true,
    "advanced_analytics": true,
    "multiple_branches": true,
    "advanced_permissions": true,
    "integrations": false,
    "api_access": false,
    "automation": false,
    "additional_storage": true
  }'::jsonb,
  1
),
(
  'enterprise',
  'Enterprise',
  'Large organizations with custom capacity and commercial terms.',
  40,
  '{}'::jsonb,
  '{
    "reports": true,
    "intelligence": true,
    "advanced_analytics": true,
    "multiple_branches": true,
    "advanced_permissions": true,
    "integrations": true,
    "api_access": true,
    "automation": true,
    "additional_storage": true
  }'::jsonb,
  1
)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  display_order = excluded.display_order,
  limits = excluded.limits,
  entitlements = excluded.entitlements,
  updated_at = timezone('utc', now());

-- Active published prices (adjust via SQL / admin later — never in Flutter).
insert into public.subscription_plan_prices (
  plan_id, billing_interval, currency, amount, price_version, is_active
)
select p.id, x.billing_interval, x.currency, x.amount, 1, true
from public.subscription_plans p
join (
  values
    ('starter', 'month', 'USD', 29.00::numeric),
    ('starter', 'year', 'USD', 290.00::numeric),
    ('professional', 'month', 'USD', 99.00::numeric),
    ('professional', 'year', 'USD', 990.00::numeric),
    ('enterprise', 'month', 'USD', null::numeric),
    ('enterprise', 'year', 'USD', null::numeric),
    ('trial', 'month', 'USD', 0::numeric),
    ('trial', 'year', 'USD', 0::numeric)
) as x(code, billing_interval, currency, amount)
  on x.code = p.code
where not exists (
  select 1
  from public.subscription_plan_prices pp
  where pp.plan_id = p.id
    and pp.billing_interval = x.billing_interval
    and pp.currency = x.currency
    and pp.is_active = true
);

alter table public.companies
  add constraint companies_plan_fkey
  foreign key (plan) references public.subscription_plans (code);

-- Expand status vocabulary with grace (soft past-due).
alter table public.companies
  drop constraint if exists companies_subscription_status_check;

alter table public.companies
  add constraint companies_subscription_status_check
    check (subscription_status in (
      'active', 'trialing', 'past_due', 'grace', 'suspended', 'cancelled'
    ));

-- Pointer to the current commercial subscription row (nullable until backfill).
alter table public.companies
  add column if not exists current_subscription_id uuid;

-- ---------------------------------------------------------------------------
-- Backfill company_subscriptions from companies.*
-- ---------------------------------------------------------------------------

insert into public.company_subscriptions (
  company_id,
  plan_id,
  plan_code,
  status,
  billing_interval,
  currency,
  unit_amount,
  plan_price_id,
  activated_at,
  expires_at,
  current_period_start
)
select
  c.id,
  p.id,
  p.code,
  case
    when c.subscription_status = 'trialing' then 'trialing'
    when c.subscription_status = 'past_due' then 'past_due'
    when c.subscription_status = 'suspended' then 'suspended'
    when c.subscription_status = 'cancelled' then 'cancelled'
    else 'active'
  end,
  'month',
  coalesce(pp.currency, 'USD'),
  pp.amount,
  pp.id,
  coalesce(c.activated_at, c.created_at, timezone('utc', now())),
  c.expires_at,
  coalesce(c.activated_at, c.created_at, timezone('utc', now()))
from public.companies c
join public.subscription_plans p on p.code = c.plan
left join lateral (
  select *
  from public.subscription_plan_prices pp
  where pp.plan_id = p.id
    and pp.billing_interval = 'month'
    and pp.is_active = true
  order by pp.effective_from desc
  limit 1
) pp on true
where c.deleted_at is null
  and not exists (
    select 1
    from public.company_subscriptions cs
    where cs.company_id = c.id
      and cs.status in ('active', 'trialing', 'past_due', 'grace')
  );

update public.companies c
set current_subscription_id = cs.id
from public.company_subscriptions cs
where cs.company_id = c.id
  and cs.status in ('active', 'trialing', 'past_due', 'grace')
  and c.current_subscription_id is null;

alter table public.companies
  drop constraint if exists companies_current_subscription_fkey;

alter table public.companies
  add constraint companies_current_subscription_fkey
  foreign key (current_subscription_id)
  references public.company_subscriptions (id)
  on delete set null;

-- ---------------------------------------------------------------------------
-- Usage / capacity / entitlement helpers
-- ---------------------------------------------------------------------------

create or replace function public.company_usage_counts(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_users integer;
  v_sales_reps integer;
  v_branches integer;
begin
  if p_company_id is null then
    return jsonb_build_object(
      'users', 0,
      'sales_representatives', 0,
      'branches', 0
    );
  end if;

  select count(*)::integer
  into v_users
  from public.employees e
  where e.company_id = p_company_id
    and e.deleted_at is null
    and e.is_active = true
    and coalesce(e.employment_status, 'active') = 'active';

  select count(*)::integer
  into v_sales_reps
  from public.employees e
  join public.roles r on r.id = e.role_id
  where e.company_id = p_company_id
    and e.deleted_at is null
    and e.is_active = true
    and coalesce(e.employment_status, 'active') = 'active'
    and r.code = 'sales_representative';

  select count(*)::integer
  into v_branches
  from public.branches b
  where b.company_id = p_company_id
    and b.deleted_at is null
    and b.is_active = true;

  return jsonb_build_object(
    'users', v_users,
    'sales_representatives', v_sales_reps,
    'branches', v_branches
  );
end;
$$;

comment on function public.company_usage_counts(uuid) is
  'Active team / sales-rep / branch usage for a company (capacity denominator).';

create or replace function public.resolve_company_plan_limits(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limits jsonb := '{}'::jsonb;
  v_overrides jsonb := '{}'::jsonb;
begin
  select coalesce(p.limits, '{}'::jsonb),
         coalesce(cs.capacity_overrides, '{}'::jsonb)
  into v_limits, v_overrides
  from public.companies c
  left join public.company_subscriptions cs
    on cs.id = c.current_subscription_id
  left join public.subscription_plans p
    on p.id = coalesce(cs.plan_id, (
      select sp.id from public.subscription_plans sp where sp.code = c.plan limit 1
    ))
  where c.id = p_company_id;

  -- Overrides win key-by-key (including explicit JSON null = unlimited).
  return coalesce(v_limits, '{}'::jsonb) || coalesce(v_overrides, '{}'::jsonb);
end;
$$;

create or replace function public.resolve_company_entitlements(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ents jsonb := '{}'::jsonb;
  v_overrides jsonb := '{}'::jsonb;
begin
  select coalesce(p.entitlements, '{}'::jsonb),
         coalesce(cs.entitlement_overrides, '{}'::jsonb)
  into v_ents, v_overrides
  from public.companies c
  left join public.company_subscriptions cs
    on cs.id = c.current_subscription_id
  left join public.subscription_plans p
    on p.id = coalesce(cs.plan_id, (
      select sp.id from public.subscription_plans sp where sp.code = c.plan limit 1
    ))
  where c.id = p_company_id;

  return coalesce(v_ents, '{}'::jsonb) || coalesce(v_overrides, '{}'::jsonb);
end;
$$;

create or replace function public.check_company_capacity(
  p_company_id uuid,
  p_limit_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_key text := lower(trim(p_limit_key));
  v_limits jsonb;
  v_usage jsonb;
  v_limit_raw jsonb;
  v_limit integer;
  v_used integer := 0;
  v_remaining integer;
  v_ratio numeric;
  v_status text;
begin
  if p_company_id is null or v_key is null or v_key = '' then
    return jsonb_build_object(
      'limit_key', v_key,
      'status', 'within',
      'unlimited', true,
      'limit_value', null,
      'used', 0,
      'remaining', null
    );
  end if;

  -- Normalize aliases.
  if v_key in ('users', 'max_user', 'team_members') then
    v_key := 'max_users';
  elsif v_key in ('sales_reps', 'sales_representatives', 'max_sales_reps') then
    v_key := 'max_sales_representatives';
  elsif v_key in ('branches', 'locations', 'max_locations') then
    v_key := 'max_branches';
  elsif v_key in ('storage', 'storage_mb') then
    v_key := 'max_storage_mb';
  end if;

  v_limits := public.resolve_company_plan_limits(p_company_id);
  v_usage := public.company_usage_counts(p_company_id);
  v_limit_raw := v_limits -> v_key;

  if v_key = 'max_users' then
    v_used := coalesce((v_usage ->> 'users')::integer, 0);
  elsif v_key = 'max_sales_representatives' then
    v_used := coalesce((v_usage ->> 'sales_representatives')::integer, 0);
  elsif v_key = 'max_branches' then
    v_used := coalesce((v_usage ->> 'branches')::integer, 0);
  else
    v_used := 0;
  end if;

  if v_limit_raw is null or v_limit_raw = 'null'::jsonb then
    return jsonb_build_object(
      'limit_key', v_key,
      'status', 'unlimited',
      'unlimited', true,
      'limit_value', null,
      'used', v_used,
      'remaining', null
    );
  end if;

  begin
    v_limit := (v_limit_raw #>> '{}')::integer;
  exception when others then
    return jsonb_build_object(
      'limit_key', v_key,
      'status', 'unlimited',
      'unlimited', true,
      'limit_value', null,
      'used', v_used,
      'remaining', null
    );
  end;

  v_remaining := greatest(v_limit - v_used, 0);

  if v_used > v_limit then
    v_status := 'exceeded';
  elsif v_used >= v_limit then
    v_status := 'at_limit';
  else
    v_ratio := case when v_limit <= 0 then 1 else v_used::numeric / v_limit::numeric end;
    if v_ratio >= 0.8 then
      v_status := 'approaching';
    else
      v_status := 'within';
    end if;
  end if;

  return jsonb_build_object(
    'limit_key', v_key,
    'status', v_status,
    'unlimited', false,
    'limit_value', v_limit,
    'used', v_used,
    'remaining', v_remaining
  );
end;
$$;

comment on function public.check_company_capacity(uuid, text) is
  'Advisory capacity check. status: within | approaching | at_limit | exceeded | unlimited.';

create or replace function public.company_has_entitlement(
  p_company_id uuid,
  p_entitlement_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_key text := lower(trim(p_entitlement_key));
  v_ents jsonb;
  v_raw jsonb;
begin
  if p_company_id is null or v_key is null or v_key = '' then
    return false;
  end if;

  v_ents := public.resolve_company_entitlements(p_company_id);
  v_raw := v_ents -> v_key;
  if v_raw is null then
    return false;
  end if;
  return coalesce((v_raw #>> '{}')::boolean, false);
end;
$$;

-- Keep companies.plan / status mirrored when current subscription changes.
create or replace function public.sync_company_subscription_mirror()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT'
     or (tg_op = 'UPDATE' and new.status is distinct from old.status)
     or (tg_op = 'UPDATE' and new.plan_code is distinct from old.plan_code)
     or (tg_op = 'UPDATE' and new.expires_at is distinct from old.expires_at)
  then
    if new.status in ('active', 'trialing', 'past_due', 'grace') then
      update public.companies
      set
        plan = new.plan_code,
        subscription_status = case
          when new.status = 'grace' then 'grace'
          else new.status
        end,
        activated_at = coalesce(new.activated_at, activated_at),
        expires_at = new.expires_at,
        current_subscription_id = new.id,
        updated_at = timezone('utc', now())
      where id = new.company_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_company_subscriptions_mirror on public.company_subscriptions;
create trigger trg_company_subscriptions_mirror
after insert or update on public.company_subscriptions
for each row execute function public.sync_company_subscription_mirror();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.subscription_plans enable row level security;
alter table public.subscription_plan_prices enable row level security;
alter table public.company_subscriptions enable row level security;

drop policy if exists "subscription_plans_select_authenticated"
  on public.subscription_plans;
create policy "subscription_plans_select_authenticated"
on public.subscription_plans
for select
to authenticated
using (is_active = true);

drop policy if exists "subscription_plan_prices_select_authenticated"
  on public.subscription_plan_prices;
create policy "subscription_plan_prices_select_authenticated"
on public.subscription_plan_prices
for select
to authenticated
using (
  is_active = true
  and exists (
    select 1
    from public.subscription_plans p
    where p.id = plan_id
      and p.is_active = true
  )
);

drop policy if exists "company_subscriptions_select_own_company"
  on public.company_subscriptions;
create policy "company_subscriptions_select_own_company"
on public.company_subscriptions
for select
to authenticated
using (company_id = public.current_company_id());

-- Writes stay service-role / future billing RPCs only (no authenticated insert).

create trigger trg_subscription_plans_set_updated_at
before update on public.subscription_plans
for each row execute function public.set_updated_at();

create trigger trg_subscription_plan_prices_set_updated_at
before update on public.subscription_plan_prices
for each row execute function public.set_updated_at();

create trigger trg_company_subscriptions_set_updated_at
before update on public.company_subscriptions
for each row execute function public.set_updated_at();

grant execute on function public.company_usage_counts(uuid) to authenticated;
grant execute on function public.resolve_company_plan_limits(uuid) to authenticated;
grant execute on function public.resolve_company_entitlements(uuid) to authenticated;
grant execute on function public.check_company_capacity(uuid, text) to authenticated;
grant execute on function public.company_has_entitlement(uuid, text) to authenticated;
