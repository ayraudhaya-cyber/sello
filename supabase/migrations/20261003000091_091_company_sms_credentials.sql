-- =============================================================================
-- 091 — Per-tenant Text.lk API tokens
--
-- Each company can have its own Text.lk token (subaccount). The token is
-- never readable by the app. Assign it once in the SQL Editor:
--
--   select public.assign_company_sms_api_token_for_sender(
--     'NamsonLanka',
--     '<token>'
--   );
--
-- Text.lk only reports the live remainder. balance_high_water is the highest
-- remainder Sello has seen for this token (the current pack). A top-up raises
-- it. Used since that pack = high-water − remaining. Re-assigning a different
-- token clears the mark so the next live read starts a new pack.
-- When no row exists, outbound SMS keeps using the shared TEXTLK_API_TOKEN
-- and the header quota stays hidden.
-- =============================================================================

create table if not exists public.company_sms_credentials (
  company_id uuid primary key references public.companies (id) on delete cascade,
  textlk_api_token text not null,
  balance_high_water integer,
  updated_at timestamptz not null default timezone('utc', now()),
  constraint company_sms_credentials_token_not_blank
    check (length(trim(textlk_api_token)) > 0),
  constraint company_sms_credentials_high_water_non_negative
    check (balance_high_water is null or balance_high_water >= 0)
);

comment on table public.company_sms_credentials is
  'Per-tenant Text.lk API token. Service role only. Never select this from the app.';

comment on column public.company_sms_credentials.balance_high_water is
  'Highest live SMS remainder seen for this token. Raised when Text.lk balance increases. Not a lifetime total.';

alter table public.company_sms_credentials enable row level security;

revoke all on table public.company_sms_credentials from public, anon, authenticated;
grant select, insert, update, delete on table public.company_sms_credentials to service_role;

create or replace function public.assign_company_sms_api_token(
  p_company_id uuid,
  p_token text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text := nullif(trim(p_token), '');
begin
  if p_company_id is null or v_token is null then
    raise exception 'A company and a Text.lk token are required.';
  end if;

  if not exists (
    select 1 from public.companies c where c.id = p_company_id
  ) then
    raise exception 'Company not found.';
  end if;

  insert into public.company_sms_credentials (
    company_id,
    textlk_api_token
  ) values (
    p_company_id,
    v_token
  )
  on conflict (company_id) do update
    set textlk_api_token = excluded.textlk_api_token,
        balance_high_water = case
          when public.company_sms_credentials.textlk_api_token
               is distinct from excluded.textlk_api_token
          then null
          else public.company_sms_credentials.balance_high_water
        end,
        updated_at = timezone('utc', now());
end;
$$;

comment on function public.assign_company_sms_api_token(uuid, text) is
  'Assigns one tenant Text.lk token. A replaced token clears the quota baseline. SQL Editor / service role only.';

revoke all on function public.assign_company_sms_api_token(uuid, text)
  from public, anon, authenticated;
grant execute on function public.assign_company_sms_api_token(uuid, text)
  to service_role;

create or replace function public.assign_company_sms_api_token_for_sender(
  p_sender_id text,
  p_token text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_count integer;
begin
  if nullif(trim(p_sender_id), '') is null then
    raise exception 'A Sender ID is required.';
  end if;

  select count(*) into v_count
  from public.company_settings cs
  where cs.sms_sender_id = trim(p_sender_id);

  if v_count = 0 then
    raise exception 'No company uses that Sender ID.';
  end if;

  if v_count > 1 then
    raise exception 'More than one company uses that Sender ID.';
  end if;

  select cs.company_id into v_company_id
  from public.company_settings cs
  where cs.sms_sender_id = trim(p_sender_id);

  perform public.assign_company_sms_api_token(v_company_id, p_token);

  return v_company_id;
end;
$$;

comment on function public.assign_company_sms_api_token_for_sender(text, text) is
  'Assigns a Text.lk token to the company that owns this Sender ID.';

revoke all on function public.assign_company_sms_api_token_for_sender(text, text)
  from public, anon, authenticated;
grant execute on function public.assign_company_sms_api_token_for_sender(text, text)
  to service_role;

-- Locks the credential row, then raises the high-water mark only when the
-- live remainder is higher. Concurrent readers wait on the row lock and then
-- see the committed mark, so two quota requests cannot lower it.
create or replace function public.record_sms_balance_high_water(
  p_company_id uuid,
  p_remaining integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_baseline integer;
begin
  if p_company_id is null or p_remaining is null or p_remaining < 0 then
    raise exception 'A company and a non-negative balance are required.';
  end if;

  select balance_high_water
    into v_baseline
  from public.company_sms_credentials
  where company_id = p_company_id
  for update;

  if not found then
    return null;
  end if;

  if v_baseline is null or p_remaining > v_baseline then
    update public.company_sms_credentials
    set balance_high_water = p_remaining,
        updated_at = timezone('utc', now())
    where company_id = p_company_id;
    v_baseline := p_remaining;
  end if;

  return v_baseline;
end;
$$;

comment on function public.record_sms_balance_high_water(uuid, integer) is
  'Raises the tenant SMS high-water mark when the live Text.lk remainder is higher. Service role only.';

revoke all on function public.record_sms_balance_high_water(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.record_sms_balance_high_water(uuid, integer)
  to service_role;

-- Session context for the quota header. Does not return the token.
create or replace function public.sms_quota_session()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'company_id', public.current_company_id(),
    'role_code', public.current_role_code()
  );
$$;

comment on function public.sms_quota_session() is
  'Company and role for the Hub SMS quota. The API token is not included.';

revoke all on function public.sms_quota_session() from public, anon;
grant execute on function public.sms_quota_session() to authenticated;
