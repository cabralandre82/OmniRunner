/**
 * check-third-party-revocation.ts
 *
 * L04-09 — CI guard for the third-party OAuth revocation primitives.
 *
 * Static checks over the migration, runbook, and finding.
 *
 * Usage: npm run audit:third-party-revocation
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const MIG = resolve(
  ROOT,
  "supabase/migrations/20260421420000_l04_09_third_party_revocation.sql",
);
const RUNBOOK = resolve(
  ROOT,
  "docs/runbooks/THIRD_PARTY_REVOCATION_RUNBOOK.md",
);
const FINDING = resolve(
  ROOT,
  "docs/audit/findings/L04-09-terceiros-strava-trainingpeaks-nao-ha-processo-de-revogacao.md",
);

interface CheckResult {
  name: string;
  ok: boolean;
  detail?: string;
}

const results: CheckResult[] = [];
function push(name: string, ok: boolean, detail?: string) {
  results.push({ name, ok, detail });
}

function safeRead(path: string, label: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    push(label, false, `missing: ${path}`);
    return null;
  }
}

const mig = safeRead(MIG, "migration present");
if (mig) {
  push("migration present", true);
  push(
    "declares third_party_revocations table",
    /CREATE TABLE IF NOT EXISTS public\.third_party_revocations/.test(mig),
  );
  push(
    "provider check constraint (strava + training_peaks)",
    /CHECK \(provider IN \('strava', 'training_peaks'\)\)/.test(mig),
  );
  push(
    "event check constraint covers 7 states",
    /'requested'[\s\S]+?'attempted'[\s\S]+?'completed'[\s\S]+?'failed'[\s\S]+?'skipped_missing_token'[\s\S]+?'skipped_provider_error_4xx'[\s\S]+?'abandoned'/.test(
      mig,
    ),
  );
  push(
    "retry_count bounded 0..20",
    /retry_count BETWEEN 0 AND 20/.test(mig),
  );
  push(
    "pending partial index present",
    /idx_third_party_revocations_pending[\s\S]+?WHERE event = 'requested'/.test(
      mig,
    ),
  );
  push(
    "RLS enabled and forced",
    /ENABLE ROW LEVEL SECURITY[\s\S]+?third_party_revocations FORCE ROW LEVEL SECURITY/.test(
      mig,
    ),
  );
  push(
    "service_role RLS policy present",
    /POLICY third_party_revocations_service_rw[\s\S]+?TO service_role/.test(
      mig,
    ),
  );
  push(
    "registers with L10-08 append-only installer",
    /fn_audit_install_append_only_guard\([\s\S]+?'third_party_revocations'/.test(
      mig,
    ),
  );

  push(
    "entry point fn_request_third_party_revocation",
    /FUNCTION public\.fn_request_third_party_revocation/.test(mig),
  );
  push(
    "worker pull fn_third_party_revocations_due",
    /FUNCTION public\.fn_third_party_revocations_due/.test(mig),
  );
  push(
    "worker writeback fn_complete_third_party_revocation",
    /FUNCTION public\.fn_complete_third_party_revocation/.test(mig),
  );

  for (const fn of [
    "fn_request_third_party_revocation",
    "fn_third_party_revocations_due",
    "fn_complete_third_party_revocation",
  ]) {
    const fnBody = extractFunctionBody(mig, fn);
    push(
      `${fn} is SECURITY DEFINER`,
      fnBody != null && /SECURITY DEFINER/.test(fnBody),
    );
    push(
      `${fn} pins search_path`,
      fnBody != null &&
        /SET search_path = public, pg_catalog, pg_temp/.test(fnBody),
    );
  }

  push(
    "grants removed from PUBLIC / anon / authenticated",
    /REVOKE ALL ON FUNCTION public\.fn_request_third_party_revocation[\s\S]+?FROM authenticated/.test(
      mig,
    ),
  );
  push(
    "grants service_role EXECUTE on each helper",
    /GRANT EXECUTE ON FUNCTION public\.fn_request_third_party_revocation[\s\S]+?TO service_role/.test(
      mig,
    ) &&
      /GRANT EXECUTE ON FUNCTION public\.fn_third_party_revocations_due[\s\S]+?TO service_role/.test(
        mig,
      ) &&
      /GRANT EXECUTE ON FUNCTION public\.fn_complete_third_party_revocation[\s\S]+?TO service_role/.test(
        mig,
      ),
  );

  push(
    "auto-enqueue trigger on strava_connections DELETE",
    /CREATE TRIGGER trg_strava_connection_revoke[\s\S]+?AFTER DELETE ON public\.strava_connections/.test(
      mig,
    ),
  );
  // The trigger function must not serialise OLD.access_token or
  // OLD.refresh_token into the JSON payload. We accept boolean
  // presence checks (`OLD.refresh_token IS NOT NULL`) — those do not
  // leak the token value itself.
  const triggerBody = extractFunctionBody(
    mig,
    "fn_strava_connection_enqueue_revocation",
  );
  push(
    "trigger function does NOT serialise token values",
    triggerBody != null &&
      !/'access_token',\s*OLD\.access_token/.test(triggerBody) &&
      !/'refresh_token',\s*OLD\.refresh_token/.test(triggerBody),
  );

  push("self-test block present", /\$L04_09_selftest\$/.test(mig));
  push(
    "self-test covers enqueue path",
    /fn_request_third_party_revocation/.test(
      mig.split("L04_09_selftest")[1] ?? "",
    ),
  );
  push(
    "self-test covers due-worker path",
    /fn_third_party_revocations_due/.test(
      mig.split("L04_09_selftest")[1] ?? "",
    ),
  );
  push(
    "self-test covers DELETE-blocked append-only path",
    /DELETE FROM public\.third_party_revocations[\s\S]+?P0010/.test(mig),
  );
  push(
    "self-test covers unknown-provider rejection (22023)",
    /'garmin'[\s\S]+?22023/.test(mig),
  );
}

const runbook = safeRead(RUNBOOK, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook describes state machine",
    /State machine|state machine/.test(runbook) &&
      /requested[\s\S]+?completed[\s\S]+?failed/.test(runbook),
  );
  push(
    "runbook includes worker pseudocode",
    /fn_third_party_revocations_due/.test(runbook) &&
      /fn_complete_third_party_revocation/.test(runbook),
  );
  push(
    "runbook describes retry budget (20)",
    /20 retries|retry_count CHECK/.test(runbook),
  );
  push(
    "runbook cross-links the migration",
    /20260421420000_l04_09_third_party_revocation\.sql/.test(runbook),
  );
  push(
    "runbook cross-links the finding",
    /L04-09/.test(runbook),
  );
  push(
    "runbook cross-links L10-08",
    /L10-08|AUDIT_LOGS_RETENTION_RUNBOOK/.test(runbook),
  );
  push(
    "runbook cross-links BACKUP_POLICY",
    /BACKUP_POLICY\.md/.test(runbook),
  );
}

const finding = safeRead(FINDING, "L04-09 finding present");
if (finding) {
  push(
    "finding references the runbook",
    /THIRD_PARTY_REVOCATION_RUNBOOK\.md/.test(finding),
  );
  push(
    "finding references the migration",
    /20260421420000_l04_09_third_party_revocation\.sql/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) {
    console.log(`[OK]   ${r.name}`);
  } else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} third-party-revocation checks passed.`,
);
if (failed > 0) {
  console.error(
    "\nL04-09 invariants broken. See docs/runbooks/THIRD_PARTY_REVOCATION_RUNBOOK.md.",
  );
  process.exit(1);
}

function extractFunctionBody(sql: string, fn: string): string | null {
  const re = new RegExp(
    `CREATE OR REPLACE FUNCTION public\\.${fn}[\\s\\S]+?\\$\\$[\\s\\S]+?\\$\\$`,
  );
  const m = sql.match(re);
  return m ? m[0] : null;
}
