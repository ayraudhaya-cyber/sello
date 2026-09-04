#!/usr/bin/env bash
# Vercel production build for Sello Flutter Web.
# Release only. Passes public Supabase client config as dart-defines.
# Never reads .env / .env.release and never forwards DX_* or server secrets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "error: SUPABASE_URL must be set in the Vercel project environment." >&2
  exit 1
fi

if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "error: SUPABASE_ANON_KEY must be set in the Vercel project environment." >&2
  exit 1
fi

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.2}"
FLUTTER_ROOT="${FLUTTER_ROOT:-${HOME}/flutter-sdk}"

if [[ ! -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  echo "Installing Flutter ${FLUTTER_VERSION} into ${FLUTTER_ROOT}"
  git clone --depth 1 --single-branch --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
fi

export PATH="${FLUTTER_ROOT}/bin:${PATH}"
flutter --version
flutter config --no-analytics --enable-web
flutter pub get

# Public web origin for Auth email redirects + customer document links.
SELLO_PUBLIC_URL="${SELLO_PUBLIC_URL:-https://sello.cashro.pro}"

# Optional short git SHA for Settings → About (Vercel injects VERCEL_GIT_COMMIT_SHA).
# Never pass secrets here — only a public commit identifier.
SELLO_GIT_SHA="${SELLO_GIT_SHA:-${VERCEL_GIT_COMMIT_SHA:-}}"
if [[ -n "${SELLO_GIT_SHA}" && "${#SELLO_GIT_SHA}" -gt 7 ]]; then
  SELLO_GIT_SHA="${SELLO_GIT_SHA:0:7}"
fi

DART_DEFINES=(
  --dart-define="SUPABASE_URL=${SUPABASE_URL}"
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
  --dart-define="SELLO_PUBLIC_URL=${SELLO_PUBLIC_URL}"
)
if [[ -n "${SELLO_GIT_SHA}" ]]; then
  DART_DEFINES+=(--dart-define="SELLO_GIT_SHA=${SELLO_GIT_SHA}")
fi

flutter build web --release "${DART_DEFINES[@]}"
