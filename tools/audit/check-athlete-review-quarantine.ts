/**
 * check-athlete-review-quarantine.ts
 *
 * L21-10 — CI guard for the athlete review quarantine primitives.
 *
 * Invariants:
 *   1. Migration adds `sessions.review_status` with CHECK state-machine.
 *   2. Migration defines `fn_session_visibility_status(uuid)` as
 *      STABLE + SECURITY DEFINER, hides `integrity_flags` from
 *      non-owners, surfaces flags only to owner/platform_admin.
 *   3. Migration creates `athlete_review_requests` with UNIQUE-open
 *      partial index, RLS enabled, policies (own read + insert,
 *      admin update), CHECKs on status/length/evidence.
 *   4. Writer RPC `fn_request_session_review(uuid, text, jsonb)`
 *      enforces ownership + reviewable state + requires flags or
 *      `is_verified=false`, and atomically flips review_status.
 *   5. BEFORE UPDATE trigger on `sessions.review_status` enforces
 *      legal transitions.
 *   6. Self-test asserts column presence, helper, trigger, and
 *      CHECK violations.
 *
 * Usage: npm run audit:athlete-review-quarantine
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
  "supabase/migrations/20260421550000_l21_10_athlete_review_quarantine.sql",
);
const mig = safeRead(migPath, "L21-10 migration present");
if (mig) {
  push(
    "adds sessions.review_status (conditional)",
    /ADD COLUMN review_status text NOT NULL DEFAULT 'none'/.test(mig),
  );
  push(
    "review_status CHECK enum",
    /chk_sessions_review_status[\s\S]{0,200}'none','pending_review','in_review','approved','rejected'/.test(
      mig,
    ),
  );

  push(
    "defines fn_session_visibility_status",
    /CREATE OR REPLACE FUNCTION public\.fn_session_visibility_status/.test(mig),
  );
  push(
    "visibility helper is STABLE + SECURITY DEFINER",
    /fn_session_visibility_status[\s\S]{0,400}STABLE[\s\S]{0,120}SECURITY DEFINER/.test(
      mig,
    ),
  );
  push(
    "non-owner branch hides integrity_flags",
    /NOT v_is_owner AND NOT v_is_admin[\s\S]{0,400}'flags_visible',\s*false/.test(
      mig,
    ),
  );
  push(
    "owner/admin branch surfaces integrity_flags",
    /'flags_visible',\s*true[\s\S]{0,200}'integrity_flags'/.test(mig),
  );
  push(
    "public neutral labels are verified/pending_review/verification_pending",
    /'verified'/.test(mig) && /'pending_review'/.test(mig) &&
      /'verification_pending'/.test(mig),
  );

  push(
    "creates athlete_review_requests table",
    /CREATE TABLE IF NOT EXISTS public\.athlete_review_requests/.test(mig),
  );
  push(
    "status CHECK enum",
    /chk_review_request_status[\s\S]{0,200}'pending','in_review','approved','rejected','auto_dismissed'/.test(
      mig,
    ),
  );
  push(
    "UNIQUE-open partial index enforced",
    /uniq_review_request_open_per_session[\s\S]{0,200}WHERE status IN \('pending','in_review'\)/.test(
      mig,
    ),
  );
  push(
    "evidence_urls must be array",
    /chk_review_request_evidence_shape[\s\S]{0,160}jsonb_typeof\(evidence_urls\) = 'array'/.test(
      mig,
    ),
  );
  push(
    "resolved pairing CHECK",
    /chk_review_request_resolved_pairing/.test(mig),
  );
  push(
    "RLS enabled on athlete_review_requests",
    /ALTER TABLE public\.athlete_review_requests ENABLE ROW LEVEL SECURITY/.test(
      mig,
    ),
  );
  push(
    "policy: own-user + admin read",
    /athlete_review_own_read[\s\S]{0,400}athlete_id = auth\.uid\(\)[\s\S]{0,400}platform_role = 'admin'/.test(
      mig,
    ),
  );
  push(
    "policy: own-user insert",
    /athlete_review_own_insert[\s\S]{0,200}FOR INSERT WITH CHECK \(athlete_id = auth\.uid\(\)\)/.test(
      mig,
    ),
  );
  push(
    "policy: admin-only update",
    /athlete_review_admin_update[\s\S]{0,400}platform_role = 'admin'/.test(mig),
  );

  push(
    "defines fn_request_session_review",
    /CREATE OR REPLACE FUNCTION public\.fn_request_session_review/.test(mig),
  );
  push(
    "request RPC requires authentication",
    /NOT_AUTHENTICATED/.test(mig),
  );
  push(
    "request RPC enforces ownership (42501)",
    /FORBIDDEN/.test(mig) && /user_id <> v_viewer/.test(mig),
  );
  push(
    "request RPC rejects already-queued sessions",
    /INVALID_STATE/.test(mig),
  );
  push(
    "request RPC rejects NOTHING_TO_REVIEW",
    /NOTHING_TO_REVIEW/.test(mig),
  );
  push(
    "request RPC flips review_status atomically",
    /UPDATE public\.sessions[\s\S]{0,200}SET review_status = 'pending_review'/.test(
      mig,
    ),
  );

  push(
    "transition guard trigger function",
    /CREATE OR REPLACE FUNCTION public\.fn_sessions_review_status_guard/.test(
      mig,
    ),
  );
  push(
    "transition trigger wired BEFORE UPDATE OF review_status",
    /trg_sessions_review_status_guard[\s\S]{0,300}BEFORE UPDATE OF review_status ON public\.sessions/.test(
      mig,
    ),
  );
  push(
    "transition trigger raises INVALID_TRANSITION",
    /INVALID_TRANSITION/.test(mig),
  );

  push(
    "self-test: review_status column missing",
    /review_status column missing/.test(mig),
  );
  push(
    "self-test: visibility helper missing",
    /fn_session_visibility_status missing/.test(mig),
  );
  push(
    "self-test: unique-open index missing",
    /unique-open index missing/.test(mig),
  );
  push(
    "self-test: bogus status rejected",
    /bogus status should have been rejected/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L21-10-anti-cheat-pode-publicamente-marcar-elite-como-suspeito.md",
);
const finding = safeRead(findingPath, "L21-10 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421550000_l21_10_athlete_review_quarantine\.sql/.test(finding),
  );
  push(
    "finding references visibility helper",
    /fn_session_visibility_status/.test(finding),
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
  `\n${results.length - failed}/${results.length} athlete-review-quarantine checks passed.`,
);
if (failed > 0) {
  console.error("\nL21-10 invariants broken.");
  process.exit(1);
}
