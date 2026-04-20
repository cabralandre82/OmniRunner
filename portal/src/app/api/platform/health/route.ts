import { type NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { metrics } from "@/lib/metrics";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * GET /api/platform/health — Admin-only detailed health snapshot.
 *
 * This is the authenticated counterpart of the public `/api/health`
 * endpoint, returning the check breakdown + invariant count that the
 * public surface deliberately hides (L06-02).
 *
 * Use this during a live incident to see, at a glance:
 *   • whether Postgres is reachable + ballpark latency
 *   • whether custody invariants are holding
 *   • how many violations exist right now (one number, not per-row
 *     detail — that still requires `/api/platform/invariants`)
 *
 * Response shape:
 *   {
 *     ok: true,
 *     status:          "ok" | "degraded" | "down",
 *     ts:              number (ms epoch),
 *     latency_ms:      number,
 *     checks: {
 *       db:            "connected" | "unreachable",
 *       invariants:    "healthy"   | "violations",
 *     },
 *     invariant_count: number,
 *     request_id:      string,
 *     checked_at:      string (ISO)
 *   }
 *
 * Errors return the canonical `{ ok: false, error: {...} }` envelope
 * with a `request_id` for trace correlation.
 *
 * Auth: platform_admins membership required. Unauthenticated callers
 * receive 401 *before* the service client is instantiated so we never
 * run the health probe on their behalf.
 *
 * Audit: docs/audit/findings/L06-02-health-check-exibe-contagem-exata-de-violacoes-info.md
 */
async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Not authenticated", status: 401 } as const;

  const { data: membership } = await supabase
    .from("platform_admins")
    .select("role")
    .eq("user_id", user.id)
    .single();

  if (!membership) return { error: "Forbidden", status: 403 } as const;

  return { user } as const;
}

// L17-01 — defense-in-depth: o handler já tem try/catch interno + envelope
// canônico, mas o wrapper externo cobre throws do `requirePlatformAdmin`
// e propaga x-request-id quando o cliente envia o header.
export const GET = withErrorHandler(_get, "api.platform.health.get");

async function _get(_req: NextRequest) {
  const requestId = randomUUID();

  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "UNAUTHORIZED",
          message: auth.error,
          request_id: requestId,
        },
      },
      { status: auth.status },
    );
  }

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
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    logger.error("platform.health.check_failed", {
      request_id: requestId,
      error: msg,
    });
    dbOk = false;
  }

  const latencyMs = Date.now() - start;
  const allOk = dbOk && invariantsOk;
  const status: "ok" | "degraded" | "down" = allOk
    ? "ok"
    : dbOk
      ? "degraded"
      : "down";

  metrics.timing("platform.health.duration", latencyMs);
  metrics.gauge("platform.health.db", dbOk ? 1 : 0);
  metrics.gauge("platform.health.invariants", invariantsOk ? 1 : 0);
  if (invariantCount > 0) {
    metrics.gauge("platform.health.invariant_violations", invariantCount);
  }

  return NextResponse.json(
    {
      ok: true,
      status,
      ts: Date.now(),
      latency_ms: latencyMs,
      checks: {
        db: dbOk ? "connected" : "unreachable",
        invariants: invariantsOk ? "healthy" : "violations",
      },
      invariant_count: invariantCount,
      request_id: requestId,
      checked_at: new Date().toISOString(),
    },
    { status: allOk ? 200 : 503 },
  );
}
