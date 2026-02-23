#!/usr/bin/env bash
#
# Pre-build validation — run before flutter build/run to verify
# that all required configuration files and env vars are in place.
#
# Usage:
#   ./scripts/preflight_check.sh .env.dev
#   ./scripts/preflight_check.sh .env.prod
#
set -euo pipefail

ENV_FILE="${1:-.env.dev}"
ERRORS=0
WARNINGS=0

red()    { printf "\033[0;31m✗ %s\033[0m\n" "$1"; }
yellow() { printf "\033[0;33m⚠ %s\033[0m\n" "$1"; }
green()  { printf "\033[0;32m✓ %s\033[0m\n" "$1"; }
header() { printf "\n\033[1;36m── %s ──\033[0m\n" "$1"; }

header "1. ENV FILE"
if [ -f "../$ENV_FILE" ]; then
  green "$ENV_FILE exists"
  source "../$ENV_FILE" 2>/dev/null || true
else
  red "$ENV_FILE NOT FOUND — copy .env.example to $ENV_FILE and fill in values"
  ERRORS=$((ERRORS + 1))
fi

header "2. SUPABASE"
if [ -n "${SUPABASE_URL:-}" ] && [ "$SUPABASE_URL" != "https://YOUR_PROJECT.supabase.co" ]; then
  green "SUPABASE_URL = $SUPABASE_URL"
else
  red "SUPABASE_URL is missing or still placeholder"
  ERRORS=$((ERRORS + 1))
fi

if [ -n "${SUPABASE_ANON_KEY:-}" ] && [ "$SUPABASE_ANON_KEY" != "eyJ..." ]; then
  green "SUPABASE_ANON_KEY is set (${#SUPABASE_ANON_KEY} chars)"
else
  red "SUPABASE_ANON_KEY is missing or still placeholder"
  ERRORS=$((ERRORS + 1))
fi

header "3. FIREBASE (google-services.json)"
if [ -f "android/app/google-services.json" ]; then
  green "google-services.json exists"
else
  red "android/app/google-services.json NOT FOUND"
  echo "    → Firebase Console → Project Settings → Add Android app"
  echo "    → Package: com.omnirunner.omni_runner"
  echo "    → Download google-services.json → place in android/app/"
  ERRORS=$((ERRORS + 1))
fi

header "4. GOOGLE SIGN-IN"
if [ -n "${GOOGLE_WEB_CLIENT_ID:-}" ] && [ "$GOOGLE_WEB_CLIENT_ID" != "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com" ]; then
  green "GOOGLE_WEB_CLIENT_ID is set"
else
  red "GOOGLE_WEB_CLIENT_ID is missing or placeholder"
  echo "    → Firebase Console → Authentication → Sign-in method → Google"
  echo "    → Copy 'Web client ID' (NOT Android client ID)"
  ERRORS=$((ERRORS + 1))
fi

header "5. MAPTILER"
if [ -n "${MAPTILER_API_KEY:-}" ] && [ "$MAPTILER_API_KEY" != "your_maptiler_key" ]; then
  green "MAPTILER_API_KEY is set"
else
  yellow "MAPTILER_API_KEY is missing — map tiles will be empty (GPS still works)"
  WARNINGS=$((WARNINGS + 1))
fi

header "6. SENTRY (optional)"
if [ -n "${SENTRY_DSN:-}" ] && [ "$SENTRY_DSN" != "https://YOUR_DSN@sentry.io/PROJECT_ID" ]; then
  green "SENTRY_DSN is set"
else
  yellow "SENTRY_DSN is missing — crash reporting disabled (app still works)"
  WARNINGS=$((WARNINGS + 1))
fi

header "7. ANDROID SIGNING (release only)"
if [ -f "android/key.properties" ]; then
  green "key.properties exists"
else
  yellow "android/key.properties not found — release builds use debug signing"
  WARNINGS=$((WARNINGS + 1))
fi

header "8. SUPABASE BACKEND"
MIGRATIONS_COUNT=$(find ../supabase/migrations -name "*.sql" 2>/dev/null | wc -l)
EF_COUNT=$(find ../supabase/functions -maxdepth 1 -type d 2>/dev/null | grep -v "_shared" | grep -v "^../supabase/functions$" | wc -l)
green "$MIGRATIONS_COUNT migrations found"
green "$EF_COUNT Edge Functions found"
echo "    → Run: cd ../supabase && supabase db push"
echo "    → Run: cd ../supabase && supabase functions deploy"

# ── Summary ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $ERRORS -eq 0 ]; then
  green "ALL CHECKS PASSED ($WARNINGS warnings)"
  echo ""
  echo "  Build command:"
  echo "  flutter run --flavor dev --dart-define-from-file=../$ENV_FILE"
  echo ""
else
  red "$ERRORS ERRORS, $WARNINGS WARNINGS — fix errors before building"
  echo ""
  exit 1
fi
