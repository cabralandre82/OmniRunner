#!/usr/bin/env bash
#
# Convenience script to run k6 load test scenarios.
#
# Usage:
#   ./run.sh [scenario] [BASE_URL]
#
# Examples:
#   ./run.sh                    # run all scenarios
#   ./run.sh api-health         # run health check only
#   ./run.sh api-health http://localhost:3000
#   ./run.sh dashboard-load https://staging.example.com
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BASE_URL="${2:-${BASE_URL:-http://localhost:3000}}"
export BASE_URL

SCENARIOS=(
  "api-health"
  "dashboard-load"
  "checkout-stress"
  "session-burst"
)

run_scenario() {
  local name="$1"
  local path="scenarios/${name}.js"
  if [[ ! -f "$path" ]]; then
    echo "Scenario not found: $path"
    return 1
  fi
  echo "=========================================="
  echo "Running: $name (BASE_URL=$BASE_URL)"
  echo "=========================================="
  k6 run -e BASE_URL="$BASE_URL" "$path"
}

if [[ -n "$1" ]]; then
  run_scenario "$1"
else
  for s in "${SCENARIOS[@]}"; do
    run_scenario "$s"
  done
fi
