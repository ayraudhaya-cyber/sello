-- =============================================================================
-- 062 — Fix document token generation (gen_random_bytes not in search_path)
--
-- prepare_order_confirmation / prepare_collection_acknowledgement call
-- encode(gen_random_bytes(24), 'hex') with search_path = public.
-- On Supabase, pgcrypto lives in the extensions schema, so unqualified
-- gen_random_bytes fails with: function gen_random_bytes(integer) does not exist.
--
-- Fix: ensure pgcrypto is installed under extensions, and expose a thin
-- public.gen_random_bytes wrapper so existing RPCs keep working.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- Public shim so security-definer RPCs with search_path=public resolve it.
create or replace function public.gen_random_bytes(len integer)
returns bytea
language sql
volatile
parallel safe
set search_path = ''
as $$
  select extensions.gen_random_bytes(len);
$$;

comment on function public.gen_random_bytes(integer) is
  'Compatibility wrapper for extensions.gen_random_bytes used by document token RPCs.';

revoke all on function public.gen_random_bytes(integer) from public;
grant execute on function public.gen_random_bytes(integer)
  to postgres, anon, authenticated, service_role;
