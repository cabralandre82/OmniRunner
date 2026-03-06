#!/usr/bin/env bash
# ============================================================================
# Billing Smoke Test — E2E validation against Asaas Sandbox
#
# Tests the 5 critical billing flows:
#   E1: Admin connects Asaas (sandbox)
#   E2: Admin assigns plan with billing to 1 athlete
#   E3: Verify Asaas subscription was created
#   E4: Admin cancels subscription
#   E5: Verify cancellation propagated
#
# Prerequisites:
#   - SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY set
#   - ASAAS_SANDBOX_KEY set (Asaas sandbox API key)
#   - jq installed
#   - A test group with admin_master user exists
#
# Usage:
#   export SUPABASE_URL="https://xxx.supabase.co"
#   export SUPABASE_SERVICE_ROLE_KEY="eyJ..."
#   export ASAAS_SANDBOX_KEY='$aact_...'
#   export TEST_GROUP_ID="uuid-of-test-group"
#   export TEST_ADMIN_JWT="eyJ..."  # JWT of admin_master user
#   bash tools/smoke_test_billing.sh
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARNINGS=()
ERRORS=()

pass() { echo -e "${GREEN}PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; ((FAIL++)); ERRORS+=("$1"); }
warn() { echo -e "${YELLOW}WARN${NC}: $1"; WARNINGS+=("$1"); }

API="${SUPABASE_URL}/functions/v1"
AUTH="Authorization: Bearer ${TEST_ADMIN_JWT}"
CT="Content-Type: application/json"

echo "============================================"
echo "  Billing Smoke Test — Asaas Sandbox E2E"
echo "============================================"
echo ""

# ── E1: Test Connection ──────────────────────────────────────────────────
echo "── E1: Test Asaas Connection ──"

RES=$(curl -s -w "\n%{http_code}" -X POST "${API}/asaas-sync" \
  -H "$AUTH" -H "$CT" \
  -d "{\"action\":\"test_connection\",\"group_id\":\"${TEST_GROUP_ID}\",\"api_key\":\"${ASAAS_SANDBOX_KEY}\",\"environment\":\"sandbox\"}")

HTTP=$(echo "$RES" | tail -1)
BODY=$(echo "$RES" | sed '$d')

if [ "$HTTP" = "200" ]; then
  CONNECTED=$(echo "$BODY" | jq -r '.connected // false')
  if [ "$CONNECTED" = "true" ]; then
    pass "E1: Asaas sandbox connection successful"
  else
    fail "E1: Connection returned 200 but connected=false"
    echo "  Response: $BODY"
  fi
else
  fail "E1: Connection failed with HTTP $HTTP"
  echo "  Response: $BODY"
fi

# ── E1b: Setup Webhook ──────────────────────────────────────────────────
echo ""
echo "── E1b: Setup Webhook ──"

RES=$(curl -s -w "\n%{http_code}" -X POST "${API}/asaas-sync" \
  -H "$AUTH" -H "$CT" \
  -d "{\"action\":\"setup_webhook\",\"group_id\":\"${TEST_GROUP_ID}\"}")

HTTP=$(echo "$RES" | tail -1)
BODY=$(echo "$RES" | sed '$d')

if [ "$HTTP" = "200" ]; then
  WH_CONFIGURED=$(echo "$BODY" | jq -r '.webhook_configured // false')
  if [ "$WH_CONFIGURED" = "true" ]; then
    pass "E1b: Webhook configured successfully"
  else
    warn "E1b: Webhook may already exist or returned unexpected response"
    echo "  Response: $BODY"
  fi
else
  fail "E1b: Webhook setup failed with HTTP $HTTP"
  echo "  Response: $BODY"
fi

# ── E2: Create Customer ─────────────────────────────────────────────────
echo ""
echo "── E2: Create Asaas Customer ──"

TEST_USER_ID="00000000-0000-0000-0000-smoke$(date +%s)"
TEST_CPF="52998224725"

RES=$(curl -s -w "\n%{http_code}" -X POST "${API}/asaas-sync" \
  -H "$AUTH" -H "$CT" \
  -d "{\"action\":\"create_customer\",\"group_id\":\"${TEST_GROUP_ID}\",\"athlete_user_id\":\"${TEST_USER_ID}\",\"name\":\"Smoke Test Runner\",\"cpf\":\"${TEST_CPF}\",\"email\":\"smoke@test.omnirunner.app\"}")

HTTP=$(echo "$RES" | tail -1)
BODY=$(echo "$RES" | sed '$d')

if [ "$HTTP" = "200" ]; then
  ASAAS_CUSTOMER_ID=$(echo "$BODY" | jq -r '.asaas_customer_id // empty')
  if [ -n "$ASAAS_CUSTOMER_ID" ]; then
    pass "E2a: Asaas customer created: $ASAAS_CUSTOMER_ID"
  else
    fail "E2a: Customer created but no asaas_customer_id returned"
  fi
else
  fail "E2a: Customer creation failed with HTTP $HTTP"
  echo "  Response: $BODY"
  ASAAS_CUSTOMER_ID=""
fi

# ── E2b: Create Subscription ────────────────────────────────────────────
echo ""
echo "── E2b: Create Asaas Subscription ──"

TEST_SUB_ID="00000000-0000-0000-0000-sub$(date +%s)"
NEXT_DUE=$(date -d "+30 days" +%Y-%m-%d 2>/dev/null || date -v+30d +%Y-%m-%d)

if [ -n "$ASAAS_CUSTOMER_ID" ]; then
  RES=$(curl -s -w "\n%{http_code}" -X POST "${API}/asaas-sync" \
    -H "$AUTH" -H "$CT" \
    -d "{\"action\":\"create_subscription\",\"group_id\":\"${TEST_GROUP_ID}\",\"subscription_id\":\"${TEST_SUB_ID}\",\"asaas_customer_id\":\"${ASAAS_CUSTOMER_ID}\",\"value\":50,\"next_due_date\":\"${NEXT_DUE}\",\"description\":\"Smoke Test Plan\"}")

  HTTP=$(echo "$RES" | tail -1)
  BODY=$(echo "$RES" | sed '$d')

  if [ "$HTTP" = "200" ]; then
    ASAAS_SUB_ID=$(echo "$BODY" | jq -r '.asaas_subscription_id // empty')
    if [ -n "$ASAAS_SUB_ID" ]; then
      pass "E2b: Asaas subscription created: $ASAAS_SUB_ID"
    else
      fail "E2b: Subscription created but no asaas_subscription_id returned"
    fi
  else
    fail "E2b: Subscription creation failed with HTTP $HTTP"
    echo "  Response: $BODY"
    ASAAS_SUB_ID=""
  fi
else
  fail "E2b: Skipped — no customer ID from E2a"
  ASAAS_SUB_ID=""
fi

# ── E3: Verify via Asaas API ────────────────────────────────────────────
echo ""
echo "── E3: Verify subscription exists in Asaas ──"

if [ -n "$ASAAS_SUB_ID" ]; then
  ASAAS_RES=$(curl -s "https://api-sandbox.asaas.com/v3/subscriptions/${ASAAS_SUB_ID}" \
    -H "access_token: ${ASAAS_SANDBOX_KEY}")

  ASAAS_STATUS=$(echo "$ASAAS_RES" | jq -r '.status // empty')

  if [ "$ASAAS_STATUS" = "ACTIVE" ]; then
    pass "E3: Asaas subscription is ACTIVE"
  elif [ -n "$ASAAS_STATUS" ]; then
    warn "E3: Asaas subscription status is $ASAAS_STATUS (expected ACTIVE)"
  else
    fail "E3: Could not verify Asaas subscription"
    echo "  Response: $ASAAS_RES"
  fi
else
  fail "E3: Skipped — no subscription ID from E2b"
fi

# ── E4: Cancel Subscription ─────────────────────────────────────────────
echo ""
echo "── E4: Cancel subscription ──"

if [ -n "$ASAAS_SUB_ID" ]; then
  RES=$(curl -s -w "\n%{http_code}" -X POST "${API}/asaas-sync" \
    -H "$AUTH" -H "$CT" \
    -d "{\"action\":\"cancel_subscription\",\"group_id\":\"${TEST_GROUP_ID}\",\"subscription_id\":\"${TEST_SUB_ID}\"}")

  HTTP=$(echo "$RES" | tail -1)
  BODY=$(echo "$RES" | sed '$d')

  if [ "$HTTP" = "200" ]; then
    CANCELLED=$(echo "$BODY" | jq -r '.cancelled // false')
    if [ "$CANCELLED" = "true" ]; then
      pass "E4: Subscription cancelled successfully"
    else
      fail "E4: Cancel returned 200 but cancelled=false"
    fi
  else
    fail "E4: Cancel failed with HTTP $HTTP"
    echo "  Response: $BODY"
  fi
else
  fail "E4: Skipped — no subscription to cancel"
fi

# ── E5: Verify cancellation ─────────────────────────────────────────────
echo ""
echo "── E5: Verify cancellation in Asaas ──"

if [ -n "$ASAAS_SUB_ID" ]; then
  sleep 2
  ASAAS_RES=$(curl -s "https://api-sandbox.asaas.com/v3/subscriptions/${ASAAS_SUB_ID}" \
    -H "access_token: ${ASAAS_SANDBOX_KEY}")

  ASAAS_STATUS=$(echo "$ASAAS_RES" | jq -r '.status // empty')

  if [ "$ASAAS_STATUS" = "INACTIVE" ] || [ "$ASAAS_STATUS" = "EXPIRED" ]; then
    pass "E5: Asaas subscription is $ASAAS_STATUS after cancellation"
  elif [ -n "$ASAAS_STATUS" ]; then
    warn "E5: Asaas subscription status is $ASAAS_STATUS (expected INACTIVE)"
  else
    fail "E5: Could not verify cancellation"
  fi
else
  fail "E5: Skipped — no subscription ID"
fi

# ── Report ───────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  SMOKE TEST REPORT"
echo "============================================"
echo -e "  ${GREEN}PASS: $PASS${NC}"
echo -e "  ${RED}FAIL: $FAIL${NC}"
echo -e "  ${YELLOW}WARN: ${#WARNINGS[@]}${NC}"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "  Failures:"
  for e in "${ERRORS[@]}"; do
    echo -e "    ${RED}• $e${NC}"
  done
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo ""
  echo "  Warnings:"
  for w in "${WARNINGS[@]}"; do
    echo -e "    ${YELLOW}• $w${NC}"
  done
fi

echo ""
[ $FAIL -eq 0 ] && echo -e "${GREEN}ALL TESTS PASSED${NC}" || echo -e "${RED}SOME TESTS FAILED${NC}"
exit $FAIL
