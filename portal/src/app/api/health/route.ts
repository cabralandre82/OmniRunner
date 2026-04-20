import { createServiceClient } from "@/lib/supabase/service";
import { metrics } from "@/lib/metrics";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * GET /api/health — Public liveness/health signal.
 *
 * Intentionally opaque. Returns ONE of:
 *
 *   { status: "ok",       ts }   → HTTP 200
 *   { status: "degraded", ts }   → HTTP 503
 *   { status: "down",     ts }   → HTTP 503
 *
 * No `checks` object, no `latencyMs`, no invariant counts.
 *
 * L06-02 — Public consumers get a boolean healthy signal that uptime
 * probes can act on; detailed diagnostics are behind authentication:
 *
 *   • GET /api/platform/health        → status + check breakdown for
 *                                        platform admins (this file's
 *                                        previous output, minus the
 *                                        invariant count leak).
 *   • GET /api/platform/invariants    → full custody + wallet-ledger
 *                                        drift detail (L08-07).
 *   • GET /api/platform/cron-health   → per-cron staleness (L06-04).
 *   • GET /api/platform/cron-sla      → per-cron duration SLA (L12-04).
 *
 * Info-leak rationale: exposing `"7 violation(s)"` to anonymous callers
 * gave attackers a free reconnaissance signal — they could watch the
 * counter change over time to infer clearing/reconcile activity and
 * time follow-up attacks to moments of known instability.  Keeping the
 * boolean alone preserves every legitimate uptime-probe use case while
 * closing the recon vector. The underlying checks still run so that
 * the HTTP status code (200 vs 503) stays meaningful.
 *
 * Audit: docs/audit/findings/L06-02-health-check-exibe-contagem-exata-de-violacoes-info.md
 *        docs/audit/findings/L01-07-get-api-health-information-disclosure.md
 */
export async function GET() {
  const start = Date.now();
  let dbOk = false;
  let invariantsOk = true;
  let invariantCount = 0;

  try {
    const db = createServiceClient();
    const { error } = await db.from("profiles").select("id").limit(1);
    dbOk = !error;

    if (dbOk) {
      const { data: violations } = await db.rpc("check_custody_invariants");
      invariantCount = violations?.length ?? 0;
      invariantsOk = invariantCount === 0;
    }
  } catch {
    dbOk = false;
  }

  const latencyMs = Date.now() - start;
  const allOk = dbOk && invariantsOk;

  // Server-side telemetry stays intact. These metrics live in our own
  // observability pipeline (Datadog/Sentry/logs), not the public HTTP
  // response — so they do NOT leak to anonymous callers.
  metrics.timing("health.check.duration", latencyMs);
  metrics.gauge("health.db", dbOk ? 1 : 0);
  metrics.gauge("health.invariants", invariantsOk ? 1 : 0);
  if (invariantCount > 0) {
    metrics.gauge("health.invariant_violations", invariantCount);
  }

  return Response.json(
    {
      status: allOk ? "ok" : dbOk ? "degraded" : "down",
      ts: Date.now(),
    },
    { status: allOk ? 200 : 503 },
  );
}
