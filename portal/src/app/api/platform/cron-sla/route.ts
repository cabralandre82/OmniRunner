import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import {
  computeCronSlaStats,
  type CronSlaSeverity,
} from "@/lib/cron-sla";
import { metrics } from "@/lib/metrics";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

/**
 * GET /api/platform/cron-sla
 *
 * Surfaces `public.fn_compute_cron_sla_stats(p_window_hours)` (L12-04)
 * to platform admins. Operators reach for this when:
 *
 *   • A staleness/health alert from L06-04 fires AND they need to
 *     check whether the offending job is silently bloating runtime
 *     (the health view shows last_status=completed, but ALL recent
 *     runs blew through the breach threshold).
 *   • A long-running job hasn't fired the L06-04 alarm yet (still
 *     running INSIDE its cycle) but operators want to inspect
 *     average / p95 / max duration trends.
 *   • Reviewing whether `cron-sla-monitor` itself is healthy.
 *   • Tuning per-cron thresholds in `public.cron_sla_thresholds`
 *     (compare current `breach_seconds` against observed p95 / max).
 *
 * Query params (all optional):
 *   - `window_hours`  ∈ 1..720 — history window the RPC scans.
 *                      Defaults to 24h. Out-of-range values are
 *                      rejected with 400 (no silent clamping —
 *                      operators get explicit feedback).
 *   - `severity_min`  ∈ {ok|warn|critical|unknown} — drop rows below
 *                      the requested severity. Defaults to `ok`
 *                      (returns everything).
 *
 * Auth: requires platform_admins membership. The underlying RPC is
 * SECURITY DEFINER + service_role only, so unauthenticated callers
 * also receive 401 *before* the service client is even instantiated.
 *
 * Audit: docs/audit/findings/L12-04-pg-cron-nao-monitora-sla-de-execucao.md
 *
 * L17-01 — defense-in-depth: o handler já tem try/catch + envelope
 * canônico, mas o wrapper externo cobre throws do `requirePlatformAdmin`
 * (e.g. supabase auth crash) e garante x-request-id quando o cliente
 * envia o header.
 */

const QuerySchema = z.object({
  window_hours: z.coerce
    .number()
    .int()
    .min(1)
    .max(720)
    .optional(),
  severity_min: z.enum(["ok", "warn", "critical", "unknown"]).optional(),
});

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

export const GET = withErrorHandler(_get, "api.platform.cron-sla.get");

async function _get(request: NextRequest) {
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

  // Parse + validate query params (default-deny: anything outside the
  // contract is rejected with 400 so we never run the RPC on
  // user-supplied junk).
  const parsed = QuerySchema.safeParse({
    window_hours:
      request.nextUrl.searchParams.get("window_hours") ?? undefined,
    severity_min:
      request.nextUrl.searchParams.get("severity_min") ?? undefined,
  });
  if (!parsed.success) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "INVALID_QUERY",
          message: parsed.error.issues.map((i) => i.message).join("; "),
          request_id: requestId,
        },
      },
      { status: 400 },
    );
  }

  const minSeverity: CronSlaSeverity = parsed.data.severity_min ?? "ok";
  const windowHours = parsed.data.window_hours ?? 24;

  try {
    const summary = await computeCronSlaStats({
      minSeverity,
      windowHours,
    });

    metrics.gauge("cron_sla.total_jobs", summary.rows.length);
    metrics.gauge(
      "cron_sla.unhealthy_jobs",
      summary.countsBySeverity.warn + summary.countsBySeverity.critical,
    );
    metrics.gauge(
      "cron_sla.critical_jobs",
      summary.countsBySeverity.critical,
    );
    metrics.gauge("cron_sla.healthy", summary.healthy ? 1 : 0);

    return NextResponse.json({
      ok: true,
      healthy: summary.healthy,
      window_hours: summary.windowHours,
      counts: summary.countsBySeverity,
      jobs: summary.rows,
      checked_at: summary.checkedAt,
      request_id: requestId,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    logger.error("platform.cron_sla.check_failed", {
      request_id: requestId,
      error: msg,
    });
    metrics.increment("cron_sla.check_error");
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "CRON_SLA_CHECK_FAILED",
          message: msg,
          request_id: requestId,
        },
      },
      { status: 500 },
    );
  }
}
