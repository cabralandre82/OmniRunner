#!/usr/bin/env bash
# ============================================================================
# test_verification_gate.sh — Prove the monetization gate is non-bypassable
#
# Sprint 22.6.0 — Tests & Proofs
#
# PREREQUISITES:
#   1. Set environment variables (or create .env alongside this script):
#        SUPABASE_URL        — e.g. https://xxx.supabase.co
#        SUPABASE_ANON_KEY   — anon/public key
#        SERVICE_ROLE_KEY    — service role key (for admin operations)
#        TEST_USER_EMAIL     — email for test user
#        TEST_USER_PASSWORD  — password for test user
#
#   2. The test user must already exist in auth.users.
#      If not, create via Supabase dashboard or:
#        curl -X POST "$SUPABASE_URL/auth/v1/signup" \
#          -H "apikey: $SUPABASE_ANON_KEY" \
#          -H "Content-Type: application/json" \
#          -d '{"email":"test@example.com","password":"Test1234!"}'
#
# WHAT THIS PROVES:
#   - stake=0 always works (any user)
#   - stake>0 blocked for UNVERIFIED (EF layer)
#   - After earning VERIFIED, stake>0 works
#   - After DOWNGRADE, stake>0 blocked again
#   - DB triggers block even direct INSERT (service_role bypass attempt)
#
# RULES (FROZEN):
#   - Docs are law
#   - ZERO admin override
#   - stake=0 free; stake>0 requires VERIFIED
#   - Server decides
# ============================================================================

set -euo pipefail

# ── Load env ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
fi

: "${SUPABASE_URL:?Set SUPABASE_URL}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY}"
: "${SERVICE_ROLE_KEY:?Set SERVICE_ROLE_KEY}"
: "${TEST_USER_EMAIL:?Set TEST_USER_EMAIL}"
: "${TEST_USER_PASSWORD:?Set TEST_USER_PASSWORD}"

BASE="$SUPABASE_URL/functions/v1"
REST="$SUPABASE_URL/rest/v1"

PASS=0
FAIL=0

# ── Helpers ─────────────────────────────────────────────────────────────────

log_pass() { PASS=$((PASS + 1)); echo "  [PASS] $1"; }
log_fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1"; }

check_status() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    log_pass "$label (HTTP $actual)"
  else
    log_fail "$label — expected $expected, got $actual"
  fi
}

check_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    log_pass "$label"
  else
    log_fail "$label — expected to contain '$needle'"
  fi
}

# ── 1. Authenticate test user ──────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " TEST: Verification Monetization Gate (Non-Bypassable)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "── Step 1: Authenticate ──────────────────────────────────────"

AUTH_RESPONSE=$(curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_USER_EMAIL\",\"password\":\"$TEST_USER_PASSWORD\"}")

JWT=$(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || true)
USER_ID=$(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])" 2>/dev/null || true)

if [[ -z "$JWT" || -z "$USER_ID" ]]; then
  echo "  [FATAL] Failed to authenticate. Check credentials."
  echo "  Response: $AUTH_RESPONSE"
  exit 1
fi

echo "  User ID: $USER_ID"
echo "  JWT: ${JWT:0:20}..."
echo ""

# ── 2. Ensure user starts as UNVERIFIED ────────────────────────────────────

echo "── Step 2: Reset to UNVERIFIED ───────────────────────────────"

curl -s -X PATCH "$REST/athlete_verification?user_id=eq.$USER_ID" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"verification_status":"UNVERIFIED","trust_score":0,"calibration_valid_runs":0,"verified_at":null,"verification_flags":"{}"}' \
  > /dev/null

# Clear test sessions
curl -s -X DELETE "$REST/sessions?user_id=eq.$USER_ID&id=like.test-gate-*" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  > /dev/null

echo "  User reset to UNVERIFIED"
echo ""

# ── 3. TEST: stake=0 with UNVERIFIED => MUST SUCCEED ──────────────────────

echo "── Test 3: Create challenge stake=0 (UNVERIFIED) ─────────────"

CHALLENGE_ID_FREE="test-gate-free-$(date +%s)"
HTTP_CODE=$(curl -s -o /tmp/test_gate_free.json -w "%{http_code}" \
  -X POST "$BASE/challenge-create" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"$CHALLENGE_ID_FREE\",
    \"type\": \"one_vs_one\",
    \"metric\": \"distance\",
    \"window_ms\": 604800000,
    \"start_mode\": \"on_accept\",
    \"entry_fee_coins\": 0,
    \"created_at_ms\": $(date +%s000),
    \"creator_display_name\": \"Test User\"
  }")

check_status "stake=0 + UNVERIFIED => 200 OK" "200" "$HTTP_CODE"
echo ""

# ── 4. TEST: stake>0 with UNVERIFIED => MUST FAIL ─────────────────────────

echo "── Test 4: Create challenge stake>0 (UNVERIFIED) ─────────────"

CHALLENGE_ID_PAID="test-gate-paid-$(date +%s)"
HTTP_CODE=$(curl -s -o /tmp/test_gate_paid.json -w "%{http_code}" \
  -X POST "$BASE/challenge-create" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"$CHALLENGE_ID_PAID\",
    \"type\": \"one_vs_one\",
    \"metric\": \"distance\",
    \"window_ms\": 604800000,
    \"start_mode\": \"on_accept\",
    \"entry_fee_coins\": 50,
    \"created_at_ms\": $(date +%s000),
    \"creator_display_name\": \"Test User\"
  }")

BODY=$(cat /tmp/test_gate_paid.json)
check_status "stake>0 + UNVERIFIED => 403" "403" "$HTTP_CODE"
check_contains "Response contains ATHLETE_NOT_VERIFIED" "ATHLETE_NOT_VERIFIED" "$BODY"
echo ""

# ── 5. Simulate VERIFIED: insert 7 valid sessions + eval ──────────────────

echo "── Step 5: Simulate 7 valid sessions ─────────────────────────"

NOW_MS=$(date +%s000)
for i in $(seq 1 7); do
  SID="test-gate-session-$i-$(date +%s)"
  DIST=$((2000 + i * 500))
  START=$((NOW_MS - 86400000 * i))
  END=$((START + 1800000))

  curl -s -X POST "$REST/sessions" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    -d "{
      \"id\": \"$SID\",
      \"user_id\": \"$USER_ID\",
      \"status\": 3,
      \"start_time_ms\": $START,
      \"end_time_ms\": $END,
      \"total_distance_m\": $DIST,
      \"moving_ms\": 1800000,
      \"is_verified\": true,
      \"integrity_flags\": []
    }" > /dev/null
done

echo "  7 verified sessions inserted"

# Trigger evaluation
echo "  Triggering eval-athlete-verification..."
EVAL_CODE=$(curl -s -o /tmp/test_gate_eval.json -w "%{http_code}" \
  -X POST "$BASE/eval-athlete-verification" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{}')

EVAL_BODY=$(cat /tmp/test_gate_eval.json)
check_status "eval-athlete-verification => 200" "200" "$EVAL_CODE"

EVAL_STATUS=$(echo "$EVAL_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('verification_status',''))" 2>/dev/null || echo "UNKNOWN")
echo "  Verification status after eval: $EVAL_STATUS"

if [[ "$EVAL_STATUS" == "VERIFIED" ]]; then
  log_pass "Status is VERIFIED after 7 clean runs"
else
  log_fail "Expected VERIFIED, got $EVAL_STATUS"
  echo "  (Trust score may be below 80. Checking...)"
  TRUST=$(echo "$EVAL_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('trust_score',0))" 2>/dev/null || echo "0")
  echo "  Trust score: $TRUST"
fi
echo ""

# ── 6. TEST: stake>0 with VERIFIED => MUST SUCCEED ────────────────────────

echo "── Test 6: Create challenge stake>0 (VERIFIED) ───────────────"

# Re-auth to get fresh JWT (in case token expired)
AUTH_RESPONSE2=$(curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_USER_EMAIL\",\"password\":\"$TEST_USER_PASSWORD\"}")
JWT2=$(echo "$AUTH_RESPONSE2" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "$JWT")

CHALLENGE_ID_PAID2="test-gate-paid2-$(date +%s)"
HTTP_CODE=$(curl -s -o /tmp/test_gate_paid2.json -w "%{http_code}" \
  -X POST "$BASE/challenge-create" \
  -H "Authorization: Bearer $JWT2" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"$CHALLENGE_ID_PAID2\",
    \"type\": \"one_vs_one\",
    \"metric\": \"distance\",
    \"window_ms\": 604800000,
    \"start_mode\": \"on_accept\",
    \"entry_fee_coins\": 100,
    \"created_at_ms\": $(date +%s000),
    \"creator_display_name\": \"Test User\"
  }")

check_status "stake>0 + VERIFIED => 200 OK" "200" "$HTTP_CODE"
echo ""

# ── 7. Simulate DOWNGRADE: insert flagged sessions + eval ──────────────────

echo "── Step 7: Simulate integrity flags => DOWNGRADE ─────────────"

for i in $(seq 1 4); do
  SID="test-gate-flagged-$i-$(date +%s)"
  START=$((NOW_MS - 86400000 * i))
  END=$((START + 600000))

  curl -s -X POST "$REST/sessions" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    -d "{
      \"id\": \"$SID\",
      \"user_id\": \"$USER_ID\",
      \"status\": 3,
      \"start_time_ms\": $START,
      \"end_time_ms\": $END,
      \"total_distance_m\": 5000,
      \"moving_ms\": 600000,
      \"is_verified\": false,
      \"integrity_flags\": [\"SPEED_IMPOSSIBLE\", \"TELEPORT\"]
    }" > /dev/null
done

echo "  4 flagged sessions inserted"

EVAL_CODE2=$(curl -s -o /tmp/test_gate_eval2.json -w "%{http_code}" \
  -X POST "$BASE/eval-athlete-verification" \
  -H "Authorization: Bearer $JWT2" \
  -H "Content-Type: application/json" \
  -d '{}')

EVAL_BODY2=$(cat /tmp/test_gate_eval2.json)
EVAL_STATUS2=$(echo "$EVAL_BODY2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('verification_status',''))" 2>/dev/null || echo "UNKNOWN")
echo "  Verification status after flagged sessions: $EVAL_STATUS2"

if [[ "$EVAL_STATUS2" == "DOWNGRADED" || "$EVAL_STATUS2" == "MONITORED" ]]; then
  log_pass "Status degraded after integrity flags ($EVAL_STATUS2)"
else
  log_fail "Expected DOWNGRADED or MONITORED, got $EVAL_STATUS2"
fi
echo ""

# ── 8. TEST: stake>0 after DOWNGRADE => MUST FAIL ─────────────────────────

echo "── Test 8: Create challenge stake>0 (DOWNGRADED) ─────────────"

CHALLENGE_ID_PAID3="test-gate-paid3-$(date +%s)"
HTTP_CODE=$(curl -s -o /tmp/test_gate_paid3.json -w "%{http_code}" \
  -X POST "$BASE/challenge-create" \
  -H "Authorization: Bearer $JWT2" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"$CHALLENGE_ID_PAID3\",
    \"type\": \"one_vs_one\",
    \"metric\": \"distance\",
    \"window_ms\": 604800000,
    \"start_mode\": \"on_accept\",
    \"entry_fee_coins\": 50,
    \"created_at_ms\": $(date +%s000),
    \"creator_display_name\": \"Test User\"
  }")

BODY3=$(cat /tmp/test_gate_paid3.json)
check_status "stake>0 + DOWNGRADED => 403" "403" "$HTTP_CODE"
check_contains "Response contains ATHLETE_NOT_VERIFIED" "ATHLETE_NOT_VERIFIED" "$BODY3"
echo ""

# ── 9. TEST: Direct DB INSERT bypass attempt (service_role) ────────────────

echo "── Test 9: Direct INSERT stake>0 via service_role (trigger) ──"

CHALLENGE_ID_BYPASS="test-gate-bypass-$(date +%s)"
BYPASS_RESPONSE=$(curl -s -o /tmp/test_gate_bypass.json -w "%{http_code}" \
  -X POST "$REST/challenges" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d "{
    \"id\": \"$CHALLENGE_ID_BYPASS\",
    \"creator_user_id\": \"$USER_ID\",
    \"status\": \"pending\",
    \"type\": \"one_vs_one\",
    \"metric\": \"distance\",
    \"window_ms\": 604800000,
    \"start_mode\": \"on_accept\",
    \"entry_fee_coins\": 100,
    \"created_at_ms\": $(date +%s000)
  }")

BYPASS_BODY=$(cat /tmp/test_gate_bypass.json 2>/dev/null || echo "")

if [[ "$BYPASS_RESPONSE" == "4"* || "$BYPASS_RESPONSE" == "5"* ]]; then
  check_contains "DB trigger blocks service_role INSERT" "ATHLETE_NOT_VERIFIED" "$BYPASS_BODY"
else
  log_fail "Direct INSERT with service_role should have been blocked by trigger (HTTP $BYPASS_RESPONSE)"
fi
echo ""

# ── 10. TEST: Direct UPDATE stake 0→>0 bypass attempt ─────────────────────

echo "── Test 10: UPDATE entry_fee_coins 0 → 100 (trigger) ────────"

UPDATE_RESPONSE=$(curl -s -o /tmp/test_gate_update.json -w "%{http_code}" \
  -X PATCH "$REST/challenges?id=eq.$CHALLENGE_ID_FREE" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entry_fee_coins": 100}')

UPDATE_BODY=$(cat /tmp/test_gate_update.json 2>/dev/null || echo "")

if [[ "$UPDATE_RESPONSE" == "4"* || "$UPDATE_RESPONSE" == "5"* ]]; then
  check_contains "DB trigger blocks UPDATE 0→100" "ATHLETE_NOT_VERIFIED" "$UPDATE_BODY"
else
  log_fail "UPDATE entry_fee 0→100 should have been blocked by trigger (HTTP $UPDATE_RESPONSE)"
fi
echo ""

# ── 11. TEST: get_verification_state RPC ───────────────────────────────────

echo "── Test 11: RPC get_verification_state ───────────────────────"

STATE_CODE=$(curl -s -o /tmp/test_gate_state.json -w "%{http_code}" \
  -X POST "$REST/rpc/get_verification_state" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $JWT2" \
  -H "Content-Type: application/json" \
  -d '{}')

check_status "get_verification_state => 200" "200" "$STATE_CODE"

STATE_BODY=$(cat /tmp/test_gate_state.json)
check_contains "Returns verification_status" "verification_status" "$STATE_BODY"
check_contains "Returns trust_score" "trust_score" "$STATE_BODY"
check_contains "Returns valid_runs_ok" "valid_runs_ok" "$STATE_BODY"
echo ""

# ── 12. TEST: RLS — user cannot UPDATE own verification_status ─────────────

echo "── Test 12: RLS blocks direct UPDATE of verification_status ──"

RLS_CODE=$(curl -s -o /tmp/test_gate_rls.json -w "%{http_code}" \
  -X PATCH "$REST/athlete_verification?user_id=eq.$USER_ID" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $JWT2" \
  -H "Content-Type: application/json" \
  -d '{"verification_status":"VERIFIED","trust_score":100}')

RLS_BODY=$(cat /tmp/test_gate_rls.json 2>/dev/null || echo "")

# With no UPDATE policy, this should either return 0 rows updated or an error
if [[ "$RLS_CODE" == "4"* ]]; then
  log_pass "RLS blocks direct UPDATE (HTTP $RLS_CODE)"
elif echo "$RLS_BODY" | grep -q '"0"'; then
  log_pass "RLS blocks direct UPDATE (0 rows affected)"
else
  # Verify the status didn't actually change
  VERIFY_CHECK=$(curl -s "$REST/athlete_verification?user_id=eq.$USER_ID&select=verification_status" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY")
  if echo "$VERIFY_CHECK" | grep -q '"VERIFIED"'; then
    log_fail "RLS did NOT block direct UPDATE — status changed to VERIFIED"
  else
    log_pass "RLS effectively blocked UPDATE (status unchanged)"
  fi
fi
echo ""

# ── Cleanup ─────────────────────────────────────────────────────────────────

echo "── Cleanup ───────────────────────────────────────────────────"

# Delete test challenges
for CID in "$CHALLENGE_ID_FREE" "$CHALLENGE_ID_PAID2" "$CHALLENGE_ID_BYPASS"; do
  curl -s -X DELETE "$REST/challenge_participants?challenge_id=eq.$CID" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" > /dev/null 2>&1
  curl -s -X DELETE "$REST/challenges?id=eq.$CID" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" > /dev/null 2>&1
done

# Delete test sessions
curl -s -X DELETE "$REST/sessions?user_id=eq.$USER_ID&id=like.test-gate-*" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" > /dev/null 2>&1

# Reset verification
curl -s -X PATCH "$REST/athlete_verification?user_id=eq.$USER_ID" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"verification_status":"UNVERIFIED","trust_score":0,"calibration_valid_runs":0,"verified_at":null,"verification_flags":"{}"}' \
  > /dev/null

echo "  Test data cleaned up"
echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════════"
echo " RESULTS: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "  SOME TESTS FAILED — review output above."
  exit 1
else
  echo "  ALL TESTS PASSED — monetization gate is non-bypassable."
  exit 0
fi
