/**
 * check-zero-participant-settle.ts
 *
 * L05-05 — CI guard for atomic zero-winner challenge settlement.
 *
 * Invariants:
 *   1. Migration extends `challenges.status` CHECK to include
 *      `'expired_no_winners'`.
 *   2. `fn_settle_challenge_no_winners(uuid)` exists, is SECURITY
 *      DEFINER with pinned search_path, and is granted EXECUTE to
 *      `service_role` only.
 *   3. Function signature: single uuid param, returns jsonb.
 *   4. Implementation uses `fn_increment_wallets_batch` for the
 *      refund write so the L18-01 wallet-mutation guard path is
 *      exercised.
 *   5. Idempotency: second call on 'expired_no_winners' /
 *      'completed' / 'cancelled' returns `noop=true`.
 *   6. Self-test block asserts CHECK acceptance, no-op on
 *      completed, and CHALLENGE_NOT_FOUND on unknown id.
 *   7. Edge function `settle-challenge` calls
 *      `fn_settle_challenge_no_winners` on both the pre-claim and
 *      post-claim "no participants" branches — NOT the plain
 *      `status = 'expired'` shortcut.
 *
 * Usage: npm run audit:zero-participant-settle
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const migPath = resolve(
  ROOT,
  "supabase/migrations/20260421470000_l05_05_zero_participant_settle.sql",
);
const mig = safeRead(migPath, "L05-05 migration present");
if (mig) {
  push(
    "CHECK lists expired_no_winners",
    /CHECK \(status IN \([\s\S]*?'expired_no_winners'[\s\S]*?\)\)/.test(mig),
  );
  push(
    "CHECK preserves existing values",
    [
      "'pending'",
      "'active'",
      "'completing'",
      "'completed'",
      "'cancelled'",
      "'expired'",
      "'expired_no_winners'",
    ].every((v) => mig.includes(v)),
  );
  push(
    "defines fn_settle_challenge_no_winners(uuid)",
    /CREATE OR REPLACE FUNCTION public\.fn_settle_challenge_no_winners\(p_challenge_id uuid\)/.test(mig),
  );
  push(
    "returns jsonb",
    /fn_settle_challenge_no_winners\(p_challenge_id uuid\)[\s\S]{0,120}RETURNS jsonb/.test(mig),
  );
  push(
    "is SECURITY DEFINER",
    /fn_settle_challenge_no_winners[\s\S]{0,200}SECURITY DEFINER/.test(mig),
  );
  push(
    "pins search_path",
    /fn_settle_challenge_no_winners[\s\S]{0,400}SET search_path = public, pg_temp/.test(mig),
  );
  push(
    "declares lock_timeout",
    /fn_settle_challenge_no_winners[\s\S]{0,400}SET lock_timeout/.test(mig),
  );
  push(
    "uses FOR UPDATE row lock",
    /FOR UPDATE/.test(mig),
  );
  push(
    "uses fn_increment_wallets_batch",
    /public\.fn_increment_wallets_batch\(v_entries\)/.test(mig),
  );
  push(
    "idempotency: noop on completed/cancelled/expired_no_winners",
    /v_challenge\.status IN \('expired_no_winners', 'completed', 'cancelled'\)/.test(mig),
  );
  push(
    "report includes refunded_users + refunded_coins + ledger_entry_count",
    /refunded_users/.test(mig) &&
      /refunded_coins/.test(mig) &&
      /ledger_entry_count/.test(mig),
  );
  push(
    "CHALLENGE_NOT_FOUND error code",
    /CHALLENGE_NOT_FOUND: %/.test(mig),
  );
  push(
    "grants EXECUTE to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_settle_challenge_no_winners\(uuid\) TO service_role/.test(mig) &&
      /REVOKE ALL ON FUNCTION public\.fn_settle_challenge_no_winners\(uuid\) FROM anon/.test(mig) &&
      /REVOKE ALL ON FUNCTION public\.fn_settle_challenge_no_winners\(uuid\) FROM authenticated/.test(mig),
  );

  push(
    "self-test: SECURITY DEFINER",
    /self-test: helper not SECURITY DEFINER/.test(mig),
  );
  push(
    "self-test: CHECK acceptance",
    /self-test: CHECK rejected expired_no_winners/.test(mig),
  );
  push(
    "self-test: noop on completed",
    /helper should have no-op''d on completed challenge/.test(mig),
  );
  push(
    "self-test: unknown id raises",
    /helper should have raised on unknown id/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );

  // Refund math hygiene: filter delta_coins < 0 on the fee side
  // and delta_coins > 0 on already_refunded side.
  push(
    "refund math filters fees with delta_coins < 0",
    /reason = 'challenge_entry_fee'[\s\S]{0,60}AND delta_coins < 0/.test(mig),
  );
  push(
    "refund math excludes prior refunds (delta_coins > 0)",
    /reason = 'challenge_entry_refund'[\s\S]{0,60}AND delta_coins > 0/.test(mig),
  );
}

const fnPath = resolve(
  ROOT,
  "supabase/functions/settle-challenge/index.ts",
);
const fn = safeRead(fnPath, "settle-challenge edge function present");
if (fn) {
  // Plural matches expected (pre-claim + post-claim branches).
  const rpcCalls = fn.match(
    /adminDb\.rpc\(\s*"fn_settle_challenge_no_winners"/g,
  ) ?? [];
  push(
    "edge function calls fn_settle_challenge_no_winners in >= 2 branches",
    rpcCalls.length >= 2,
    `found ${rpcCalls.length}`,
  );

  // No lingering plain-expired shortcut for the zero-participant path.
  const badExpiredShortcut = /update\(\{ status: "expired" \}\)\.eq\("id", ch\.id\)/.test(fn);
  push(
    "no plain status='expired' shortcut left in settle-challenge",
    !badExpiredShortcut || /STAKE_LIMIT_EXCEEDED/.test(fn),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L05-05-challenge-ganhador-de-zero-participantes.md",
);
const finding = safeRead(findingPath, "L05-05 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421470000_l05_05_zero_participant_settle\.sql/.test(finding),
  );
  push(
    "finding references settle-challenge",
    /supabase\/functions\/settle-challenge\/index\.ts/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} zero-participant-settle checks passed.`);
if (failed > 0) {
  console.error("\nL05-05 invariants broken.");
  process.exit(1);
}
