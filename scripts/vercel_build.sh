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

flutter build web --release \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
