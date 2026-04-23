/**
 * check-challenge-withdraw-cutoff.ts
 *
 * L05-04 — CI guard for challenge withdraw-cutoff.
 *
 * Invariants:
 *   1. Migration adds `withdraw_cutoff_hours` with default 48 and
 *      a CHECK constraint that pins 0 <= value <= 168.
 *   2. Migration backfills `one_vs_one` challenges to 0 so duels
 *      keep pre-L05-04 semantics.
 *   3. Edge function `challenge-withdraw` selects
 *      `ends_at_ms, withdraw_cutoff_hours` from `challenges` and
 *      returns 422 `WITHDRAW_LOCKED` when now + cutoff >=
 *      ends_at_ms.
 *   4. The cutoff check runs BEFORE the wallet refund happens
 *      (otherwise an athlete could withdraw during the lockout,
 *      eat the 422, and still receive the refund).
 *
 * Usage: npm run audit:challenge-withdraw-cutoff
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
  "supabase/migrations/20260421460000_l05_04_challenge_withdraw_cutoff.sql",
);
const mig = safeRead(migPath, "L05-04 migration present");
if (mig) {
  push(
    "adds withdraw_cutoff_hours column NOT NULL default 48",
    /ADD COLUMN IF NOT EXISTS withdraw_cutoff_hours integer NOT NULL DEFAULT 48/i.test(mig),
  );
  push(
    "declares CHECK constraint",
    /CONSTRAINT challenges_withdraw_cutoff_hours_range/.test(mig),
  );
  push(
    "CHECK bounds [0, 168]",
    /withdraw_cutoff_hours >= 0 AND withdraw_cutoff_hours <= 168/.test(mig),
  );
  push(
    "COMMENT ON COLUMN references L05-04",
    /COMMENT ON COLUMN public\.challenges\.withdraw_cutoff_hours[\s\S]{0,120}L05-04/.test(mig),
  );
  push(
    "duels backfill to 0",
    /SET withdraw_cutoff_hours = 0[\s\S]{0,80}type = 'one_vs_one'/.test(mig),
  );
  push(
    "self-test asserts default 48",
    /'L05-04 self-test: default not 48/.test(mig),
  );
  push(
    "self-test asserts CHECK blocks negative",
    /'L05-04 self-test: CHECK did not block negative/.test(mig),
  );
  push(
    "self-test asserts CHECK blocks > 168",
    /'L05-04 self-test: CHECK did not block value > 168/.test(mig),
  );
  push(
    "self-test asserts duels backfill",
    /'L05-04 self-test: duels backfill incomplete/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const fnPath = resolve(
  ROOT,
  "supabase/functions/challenge-withdraw/index.ts",
);
const fn = safeRead(fnPath, "challenge-withdraw function present");
if (fn) {
  push(
    "edge function selects ends_at_ms + withdraw_cutoff_hours",
    /\.select\("id,\s*status,\s*entry_fee_coins,\s*creator_user_id,\s*ends_at_ms,\s*withdraw_cutoff_hours"\)/.test(fn),
  );
  push(
    "reads withdraw_cutoff_hours into cutoffHours",
    /const cutoffHours = Number\(challenge\.withdraw_cutoff_hours \?\? 0\);/.test(fn),
  );
  push(
    "reads ends_at_ms into endsAtMs",
    /challenge\.ends_at_ms/.test(fn),
  );
  push(
    "computes cutoff against Date.now()",
    /Date\.now\(\)/.test(fn) && /cutoffHours \* 3600 \* 1000/.test(fn),
  );
  push(
    "returns 422 WITHDRAW_LOCKED on cutoff",
    /jsonErr\(\s*422,\s*"WITHDRAW_LOCKED"/.test(fn),
  );
  push(
    "sets errorCode WITHDRAW_LOCKED for observability",
    /errorCode = "WITHDRAW_LOCKED";/.test(fn),
  );

  // Ordering assertion: cutoff check must appear BEFORE creditWallets.
  const cutoffIdx = fn.indexOf('"WITHDRAW_LOCKED"');
  const refundIdx = fn.indexOf("creditWallets(");
  push(
    "cutoff check runs BEFORE wallet refund",
    cutoffIdx > 0 && refundIdx > 0 && cutoffIdx < refundIdx,
  );

  // Ordering: cutoff check after status check (consistent with "cannot
  // withdraw from a completed challenge" which is a different error).
  const statusIdx = fn.indexOf('"INVALID_STATUS"');
  push(
    "cutoff check runs AFTER status precondition",
    statusIdx > 0 && cutoffIdx > 0 && statusIdx < cutoffIdx,
  );

  // Defensive: if ends_at_ms is null we do NOT block. Open-ended
  // group challenges keep pre-L05-04 behaviour.
  push(
    "null ends_at_ms bypasses the cutoff check",
    /endsAtMs !== null && Number\.isFinite\(endsAtMs\)/.test(fn),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L05-04-challenge-championship-participante-pode-retirar-se-withdraw.md",
);
const finding = safeRead(findingPath, "L05-04 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421460000_l05_04_challenge_withdraw_cutoff\.sql/.test(finding),
  );
  push(
    "finding references edge function",
    /supabase\/functions\/challenge-withdraw\/index\.ts/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} challenge-withdraw-cutoff checks passed.`);
if (failed > 0) {
  console.error("\nL05-04 invariants broken.");
  process.exit(1);
}
