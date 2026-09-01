-- =============================================================================
-- Migration 005 — Company subscription foundation
--
-- Minimal, company-level subscription state so future billing providers can be
-- added without redesigning the tenant model.
--
-- Current business rule:
--   Every provisioned company starts on Professional / Active with no expiry.
-- =============================================================================

alter table public.companies
  add column plan text,
  add column subscription_status text,
  add column activated_at timestamptz,
  add column expires_at timestamptz;

update public.companies
set
  plan = coalesce(plan, 'professional'),
  subscription_status = coalesce(subscription_status, 'active'),
  activated_at = coalesce(activated_at, created_at)
where
  plan is null
  or subscription_status is null
  or activated_at is null;

alter table public.companies
  alter column plan set default 'professional',
  alter column plan set not null,
  alter column subscription_status set default 'active',
  alter column subscription_status set not null,
  alter column activated_at set default timezone('utc', now()),
  alter column activated_at set not null;

alter table public.companies
  add constraint companies_plan_check
    check (plan in ('professional', 'trial', 'starter', 'enterprise')),
  add constraint companies_subscription_status_check
    check (subscription_status in ('active', 'trialing', 'past_due', 'suspended', 'cancelled')),
  add constraint companies_subscription_expiry_check
    check (expires_at is null or expires_at >= activated_at);

create index companies_plan_idx
  on public.companies (plan)
  where deleted_at is null;

create index companies_subscription_status_idx
  on public.companies (subscription_status)
  where deleted_at is null;

-- Existing provisioning inserts do not need to change:
-- table defaults now assign Professional / Active / activated_at automatically.
