#!/usr/bin/env bash
# =============================================================================
# Deploy Google Play Billing backend (migrasi + edge functions).
#
# Prasyarat:
#   1. `npx supabase login` sudah dilakukan
#   2. File service account: secrets/google-service-account.json
#   3. Env: SUPABASE_PROJECT_REF, RTDN_AUDIENCE, RTDN_SERVICE_ACCOUNT_EMAIL
#
# Pemakaian:
#   SUPABASE_PROJECT_REF=xxxx \
#   RTDN_AUDIENCE="https://xxxx.supabase.co/functions/v1/play-rtdn" \
#   RTDN_SERVICE_ACCOUNT_EMAIL="play-rtdn-push@proj.iam.gserviceaccount.com" \
#   ./scripts/deploy-play-billing.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REF="${SUPABASE_PROJECT_REF:-oljiqzttttxjrbwtfzze}"
SA_FILE="${GOOGLE_SERVICE_ACCOUNT_FILE:-secrets/google-service-account.json}"
PKG="${PLAY_PACKAGE_NAME:-com.qrcheck.app.qr_check}"
PRODUCT="${PLAY_PRODUCT_ID:-pro_lifetime}"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v npx >/dev/null || fail "npx tidak ditemukan"
[ -f "$SA_FILE" ] || fail "Service account JSON tidak ada: $SA_FILE"

HAS_RTDN=1
if [ -z "${RTDN_AUDIENCE:-}" ] || [ -z "${RTDN_SERVICE_ACCOUNT_EMAIL:-}" ]; then
  HAS_RTDN=0
  printf '\033[1;33m! RTDN_AUDIENCE / RTDN_SERVICE_ACCOUNT_EMAIL belum di-set — RTDN dilewati.\033[0m\n'
fi

step "Cek login Supabase"
npx --yes supabase projects list >/dev/null 2>&1 || fail "Belum login. Jalankan: npx supabase login"

step "Link project $REF"
npx --yes supabase link --project-ref "$REF" --yes || true

step "Push migrasi database"
npx --yes supabase db push

step "Set secrets function"
SECRETS=(
  "GOOGLE_SERVICE_ACCOUNT_JSON=$(cat "$SA_FILE")"
  "PLAY_PACKAGE_NAME=$PKG"
  "PLAY_PRODUCT_ID=$PRODUCT"
)
if [ "$HAS_RTDN" = "1" ]; then
  SECRETS+=("RTDN_AUDIENCE=$RTDN_AUDIENCE")
  SECRETS+=("RTDN_SERVICE_ACCOUNT_EMAIL=$RTDN_SERVICE_ACCOUNT_EMAIL")
fi
npx --yes supabase secrets set "${SECRETS[@]}"

step "Deploy verify-play-purchase"
npx --yes supabase functions deploy verify-play-purchase --project-ref "$REF"

if [ "$HAS_RTDN" = "1" ]; then
  step "Deploy play-rtdn (verify_jwt=false via config.toml)"
  npx --yes supabase functions deploy play-rtdn --project-ref "$REF"
else
  printf '\033[1;33m! play-rtdn belum di-deploy (tunggu topic Pub/Sub siap).\033[0m\n'
fi

step "Health check"
echo -n "verify-play-purchase: "
curl -fsS "https://$REF.supabase.co/functions/v1/verify-play-purchase" || echo "(gagal)"
echo
if [ "$HAS_RTDN" = "1" ]; then
  echo -n "play-rtdn           : "
  curl -fsS "https://$REF.supabase.co/functions/v1/play-rtdn" || echo "(gagal)"
  echo
fi
printf '\n\033[1;32m✓ Selesai.\033[0m\n'
[ "$HAS_RTDN" = "1" ] || printf '\033[1;33m  Langkah berikutnya: buat Pub/Sub topic+subscription, lalu jalankan ulang script ini dengan RTDN_AUDIENCE & RTDN_SERVICE_ACCOUNT_EMAIL.\033[0m\n'
