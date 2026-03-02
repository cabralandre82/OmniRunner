#!/usr/bin/env bash
# QA Section 5: "NO MONEY IN APP" CI gate
#
# Scans the Flutter app for prohibited monetary terms.
# Exits 0 if clean, 1 if violations found.
# Safe to run in CI — read-only, no side effects.

set -euo pipefail

APP_DIR="${1:-$(dirname "$0")/../../omni_runner/lib}"

if [ ! -d "$APP_DIR" ]; then
  echo "ERROR: App directory not found: $APP_DIR"
  exit 1
fi

echo "=== QA: NO MONEY IN APP ==="
echo "Scanning: $APP_DIR"
echo ""

PROHIBITED_PATTERNS=(
  'R\$'
  '€'
  'US\$'
  '\bUSD\b'
  '\bBRL\b'
  '\bdinheiro\b'
  '\bpreço\b'
  '\bpreco\b'
  '\btaxa\b'
  '\bfee\b'
  '\bpagamento\b'
  '\bpagar\b'
  '\bresgate\b'
  '\bsaque\b'
  '\bwithdraw\b'
  '\bcash\b'
  '\bmoney\b'
  '\bcobrança\b'
  '\bcobranca\b'
)

ALLOWED_PATTERNS=(
  'entryFeeCoins'
  '_feeCtrl'
  'feeCoins'
  'FeeRate'
  'fee_rate'
  'challengeFee'
  'feedItem'
  'feedList'
  'Feed'
  'taxa de vitória'
  'taxa de participação'
  'import '
  '//'
)

SCAN_DIRS=(
  "presentation"
  "core/analytics"
)

VIOLATIONS=0
VIOLATION_LOG=""

for subdir in "${SCAN_DIRS[@]}"; do
  target="$APP_DIR/$subdir"
  [ -d "$target" ] || continue

  for pattern in "${PROHIBITED_PATTERNS[@]}"; do
    matches=$(rg -i -n "$pattern" --type dart "$target" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      while IFS= read -r line; do
        is_allowed=false
        for allowed in "${ALLOWED_PATTERNS[@]}"; do
          if echo "$line" | grep -qi "$allowed"; then
            is_allowed=true
            break
          fi
        done
        if [ "$is_allowed" = false ]; then
          VIOLATIONS=$((VIOLATIONS + 1))
          VIOLATION_LOG+="  $line"$'\n'
        fi
      done <<< "$matches"
    fi
  done
done

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: Found $VIOLATIONS monetary term(s) in app code:"
  echo ""
  echo "$VIOLATION_LOG"
  echo ""
  echo "Fix these before merging."
  exit 1
else
  echo "OK: No monetary terms found in app code."
  echo ""
  exit 0
fi
