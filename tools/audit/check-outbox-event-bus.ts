/**
 * check-outbox-event-bus.ts
 *
 * L18-05 — CI guard for the durable outbox event bus.
 *
 * Invariants:
 *   1. Migration creates `public.outbox_events` with UNIQUE(event_key),
 *      CHECK on status / event_type / aggregate_type, length clamps on
 *      event_key/last_error, and attempts bounded.
 *   2. 4 indexes present (ready, aggregate, type+time, dead).
 *   3. RLS enabled with admin-only SELECT policy.
 *   4. BEFORE UPDATE trigger bumps updated_at.
 *   5. Writer `fn_outbox_emit` is SECURITY DEFINER, service-role only,
 *      rejects empty event_key, and uses ON CONFLICT DO NOTHING for
 *      idempotency.
 *   6. Consumer lifecycle: `fn_outbox_claim` uses FOR UPDATE SKIP
 *      LOCKED + visibility timer + bounds; `fn_outbox_complete`,
 *      `fn_outbox_fail`, `fn_outbox_dlq` exist and are service-role only.
 *   7. `fn_emit_session_verified` trigger wired AFTER UPDATE OF
 *      is_verified and fails-open (RAISE WARNING, not EXCEPTION).
 *   8. 30-day retention registered conditional on the retention table.
 *   9. Self-test covers emit, dedup, empty-key, bogus type, complete.
 *
 * Usage: npm run audit:outbox-event-bus
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
  "supabase/migrations/20260421540000_l18_05_outbox_event_bus.sql",
);
const mig = safeRead(migPath, "L18-05 migration present");
if (mig) {
  push(
    "creates outbox_events table",
    /CREATE TABLE IF NOT EXISTS public\.outbox_events/.test(mig),
  );
  push(
    "UNIQUE(event_key) constraint",
    /CONSTRAINT outbox_events_event_key_unique UNIQUE \(event_key\)/.test(mig),
  );
  push(
    "status CHECK enum",
    /chk_outbox_status[\s\S]{0,200}'pending','processing','completed','failed','dead'/.test(
      mig,
    ),
  );
  push(
    "event_type CHECK includes session.verified",
    /chk_outbox_event_type[\s\S]{0,800}'session\.verified'[\s\S]{0,800}'coin\.burned'/.test(
      mig,
    ),
  );
  push(
    "aggregate_type CHECK bounded",
    /chk_outbox_aggregate_type[\s\S]{0,400}'session'[\s\S]{0,200}'wallet'/.test(
      mig,
    ),
  );
  push(
    "event_key length CHECK",
    /chk_outbox_event_key_length[\s\S]{0,120}length\(event_key\) BETWEEN 1 AND 200/.test(
      mig,
    ),
  );
  push(
    "last_error length CHECK",
    /chk_outbox_last_error_length[\s\S]{0,120}length\(last_error\) <= 2000/.test(
      mig,
    ),
  );
  push(
    "attempts CHECK bounded",
    /chk_outbox_attempts[\s\S]{0,120}attempts >= 0 AND attempts <= 100/.test(mig),
  );
  push(
    "completed_at CHECK enforces pairing",
    /chk_outbox_completed_at/.test(mig),
  );

  push(
    "idx_ready partial on status",
    /idx_outbox_events_ready[\s\S]{0,200}WHERE status IN \('pending','processing'\)/.test(
      mig,
    ),
  );
  push(
    "idx_aggregate composite",
    /idx_outbox_events_aggregate[\s\S]{0,200}\(aggregate_type, aggregate_id, created_at DESC\)/.test(
      mig,
    ),
  );
  push(
    "idx_type_time composite",
    /idx_outbox_events_type_time[\s\S]{0,200}\(event_type, created_at DESC\)/.test(
      mig,
    ),
  );
  push(
    "idx_dead partial",
    /idx_outbox_events_dead[\s\S]{0,200}WHERE status IN \('failed','dead'\)/.test(
      mig,
    ),
  );

  push(
    "RLS enabled on outbox_events",
    /ALTER TABLE public\.outbox_events ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "admin-only SELECT policy",
    /outbox_events_admin_only[\s\S]{0,300}platform_role = 'admin'/.test(mig),
  );

  push(
    "updated_at trigger installed",
    /trg_outbox_touch_updated_at[\s\S]{0,200}BEFORE UPDATE ON public\.outbox_events/.test(
      mig,
    ),
  );

  push(
    "defines fn_outbox_emit",
    /CREATE OR REPLACE FUNCTION public\.fn_outbox_emit/.test(mig),
  );
  push(
    "emit is SECURITY DEFINER",
    /fn_outbox_emit[\s\S]{0,600}SECURITY DEFINER/.test(mig),
  );
  push(
    "emit service-role only",
    /REVOKE ALL ON FUNCTION public\.fn_outbox_emit[\s\S]{0,300}GRANT EXECUTE ON FUNCTION public\.fn_outbox_emit[\s\S]{0,120}service_role/.test(
      mig,
    ),
  );
  push(
    "emit uses ON CONFLICT DO NOTHING",
    /ON CONFLICT ON CONSTRAINT outbox_events_event_key_unique DO NOTHING/.test(
      mig,
    ),
  );
  push(
    "emit rejects empty event_key",
    /INVALID_EVENT_KEY/.test(mig),
  );

  push(
    "defines fn_outbox_claim",
    /CREATE OR REPLACE FUNCTION public\.fn_outbox_claim/.test(mig),
  );
  push(
    "claim uses FOR UPDATE SKIP LOCKED",
    /FOR UPDATE SKIP LOCKED/.test(mig),
  );
  push(
    "claim clamps limit [1, 1000]",
    /greatest\(1, least\(coalesce\(p_limit, 50\), 1000\)\)/.test(mig),
  );
  push(
    "claim clamps visibility [5, 3600]",
    /greatest\(5, least\(coalesce\(p_visibility_seconds, 60\), 3600\)\)/.test(
      mig,
    ),
  );
  push(
    "claim flips status to processing",
    /status\s*=\s*'processing'/.test(mig),
  );

  push(
    "defines fn_outbox_complete",
    /CREATE OR REPLACE FUNCTION public\.fn_outbox_complete/.test(mig),
  );
  push(
    "defines fn_outbox_fail",
    /CREATE OR REPLACE FUNCTION public\.fn_outbox_fail/.test(mig),
  );
  push(
    "fail flips to dead when attempts exceed max",
    /v_new_status\s*:=\s*'dead'/.test(mig),
  );
  push(
    "fail re-queues as pending when retriable",
    /SET status = 'pending'[\s\S]{0,120}WHERE id = p_id/.test(mig),
  );
  push(
    "defines fn_outbox_dlq",
    /CREATE OR REPLACE FUNCTION public\.fn_outbox_dlq/.test(mig),
  );

  push(
    "session-verified trigger function defined",
    /CREATE OR REPLACE FUNCTION public\.fn_emit_session_verified/.test(mig),
  );
  push(
    "session trigger wired AFTER UPDATE OF is_verified",
    /trg_emit_session_verified[\s\S]{0,400}AFTER UPDATE OF is_verified ON public\.sessions/.test(
      mig,
    ),
  );
  push(
    "session trigger fails open (RAISE WARNING not EXCEPTION)",
    /WHEN OTHERS THEN[\s\S]{0,200}RAISE WARNING 'L18-05/.test(mig),
  );

  push(
    "registers 30-day retention (conditional)",
    /audit_logs_retention_config[\s\S]{0,400}'outbox_events'[\s\S]{0,80}30/.test(
      mig,
    ) && /IF EXISTS[\s\S]{0,200}audit_logs_retention_config/.test(mig),
  );

  push(
    "self-test: happy path writer",
    /emit returned NULL id/.test(mig),
  );
  push(
    "self-test: duplicate dedup",
    /duplicate emit should have returned NULL/.test(mig),
  );
  push(
    "self-test: empty event_key raises 22023",
    /empty event_key should have raised 22023/.test(mig),
  );
  push(
    "self-test: bogus event_type blocked",
    /bogus event_type should have been blocked/.test(mig),
  );
  push(
    "self-test: complete flips status",
    /complete did not flip status/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L18-05-event-bus-inexistente-cascatas-de-efeitos-em-codigo.md",
);
const finding = safeRead(findingPath, "L18-05 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421540000_l18_05_outbox_event_bus\.sql/.test(finding),
  );
  push(
    "finding references canonical outbox table",
    /outbox_events/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} outbox-event-bus checks passed.`,
);
if (failed > 0) {
  console.error("\nL18-05 invariants broken.");
  process.exit(1);
}
