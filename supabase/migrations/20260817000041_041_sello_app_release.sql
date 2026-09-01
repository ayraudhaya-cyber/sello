-- =============================================================================
-- 041 — Public Sello app-release manifest (update checking)
--
-- One platform-wide row. Safe to read with the anon key — no secrets.
-- Android/iOS APKs already have SUPABASE_URL, so they can check without a
-- separate hosted JSON URL. File URL (SELLO_RELEASE_MANIFEST_URL) still wins.
-- =============================================================================

create table if not exists public.sello_app_release (
  id smallint primary key default 1 check (id = 1),
  payload jsonb not null,
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.sello_app_release is
  'Single public Sello release document for in-app update checks.';

alter table public.sello_app_release enable row level security;

revoke all on table public.sello_app_release from anon, authenticated, public;
grant select on table public.sello_app_release to anon, authenticated;

drop policy if exists sello_app_release_public_read on public.sello_app_release;
create policy sello_app_release_public_read
  on public.sello_app_release
  for select
  to anon, authenticated
  using (true);

insert into public.sello_app_release (id, payload)
values (
  1,
  '{
    "schema_version": 1,
    "app": "sello",
    "latest": {
      "version": "1.0.1",
      "build": 2,
      "released_at": "2026-08-17",
      "notes": "Testing the update flow."
    },
    "minimum": {
      "version": "1.0.0",
      "build": 1,
      "enforced": false
    },
    "platforms": {
      "android": {
        "destination_kind": "apk",
        "destination_url": ""
      },
      "ios": {
        "destination_kind": "testflight",
        "destination_url": ""
      },
      "web": {
        "destination_kind": "web",
        "destination_url": ""
      }
    }
  }'::jsonb
)
on conflict (id) do update
set
  payload = excluded.payload,
  updated_at = timezone('utc', now());
