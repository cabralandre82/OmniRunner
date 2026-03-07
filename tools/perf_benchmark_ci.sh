#!/usr/bin/env bash
# =============================================================================
# Performance Benchmark CI
# =============================================================================
# Runs perf_benchmark.sql against a database, parses EXPLAIN ANALYZE output,
# checks no query exceeds 100ms, outputs JSON for CI consumption.
#
# Usage:
#   SUPABASE_DB_URL='postgresql://...' ./tools/perf_benchmark_ci.sh
#
# Exit: 0 if all queries pass, 1 if any query exceeds 100ms
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAX_MS=100

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo '{"error": "SUPABASE_DB_URL not set", "skipped": true}'
  exit 0
fi

OUTPUT=$(psql "$SUPABASE_DB_URL" -f "$REPO_ROOT/tools/perf_benchmark.sql" 2>&1) || true

# Parse "Execution Time: X.XXX ms" from EXPLAIN ANALYZE output
declare -a TIMES
declare -a NAMES
QUERY_NAMES=(
  "1. KPIs daily"
  "2. Members with status"
  "3. Sessions with attendance count"
  "4. Unresolved alerts"
  "5. Workout assignments"
  "6. Announcements with read status"
  "7. Financial ledger"
  "8. Active athletes per group"
  "9. Subscriptions with plan"
  "10. Full CRM with tags"
  "11. Athlete KPIs"
  "12. CRM attendance aggregation"
)

idx=0
while IFS= read -r line; do
  if [[ "$line" =~ Execution\ Time:\ ([0-9.]+)\ ms ]]; then
    ms="${BASH_REMATCH[1]}"
    name="${QUERY_NAMES[$idx]:-Query $((idx + 1))}"
    TIMES+=("$ms")
    NAMES+=("$name")
    idx=$((idx + 1))
  fi
done <<< "$OUTPUT"

# Build JSON output
JSON_QUERIES=""
all_passed=true
max_time=0

for i in "${!TIMES[@]}"; do
  ms="${TIMES[$i]}"
  name="${NAMES[$i]}"
  if awk -v m="$ms" -v max="$MAX_MS" 'BEGIN { exit (m <= max) ? 0 : 1 }'; then
    passed="true"
  else
    passed="false"
    all_passed=false
  fi
  if awk -v m="$ms" -v mx="$max_time" 'BEGIN { exit (m > mx) ? 0 : 1 }' 2>/dev/null; then
    max_time="$ms"
  fi
  entry="{\"name\": \"$name\", \"execution_time_ms\": $ms, \"passed\": $passed}"
  if [[ -n "$JSON_QUERIES" ]]; then
    JSON_QUERIES="$JSON_QUERIES, $entry"
  else
    JSON_QUERIES="$entry"
  fi
done

if [[ ${#TIMES[@]} -eq 0 ]]; then
  echo "{\"error\": \"No benchmark results parsed. Database may need perf_seed.\", \"raw_preview\": \"${OUTPUT:0:200}...\"}"
  exit 1
fi

echo "{\"queries\": [$JSON_QUERIES], \"all_passed\": $all_passed, \"max_time_ms\": $max_time, \"threshold_ms\": $MAX_MS}"

if [[ "$all_passed" != "true" ]]; then
  exit 1
fi
exit 0
