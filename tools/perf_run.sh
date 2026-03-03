#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

echo "=== Performance Test Suite ==="
echo ""
echo "Project: $PROJECT_DIR"
echo "DB:      $DB_URL"
echo ""

# ── Step 1: Seed ─────────────────────────────────────────────────────────────
echo "▶ Step 1: Seeding test data..."
echo ""
NODE_PATH="$PROJECT_DIR/portal/node_modules" npx tsx "$SCRIPT_DIR/perf_seed.ts"

# ── Step 2: Benchmark ────────────────────────────────────────────────────────
echo ""
echo "▶ Step 2: Running SQL benchmarks..."
echo ""

if command -v psql &>/dev/null; then
  psql "$DB_URL" -f "$SCRIPT_DIR/perf_benchmark.sql"
else
  echo "  psql not found — run manually:"
  echo "  psql '$DB_URL' -f tools/perf_benchmark.sql"
fi

# ── Step 3: Cleanup prompt ───────────────────────────────────────────────────
echo ""
echo "▶ Step 3: Cleanup"
echo ""
echo "  Seed data is still in the database."
echo "  To remove it, run:"
echo ""
echo "    NODE_PATH=portal/node_modules npx tsx tools/perf_seed.ts --cleanup"
echo ""
