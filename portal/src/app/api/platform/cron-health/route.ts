import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { checkCronHealth, type CronSeverity } from "@/lib/cron-health";
import { metrics } from "@/lib/metrics";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

/**
 * GET /api/platform/cron-health
 *
 * Aggregates `public.fn_check_cron_health()` (L06-04) into a single
 * platform-admin endpoint. Operators reach for this when:
 *
 *   • The CRON_HEALTH_RUNBOOK §2 dashboard query is needed but they
 *     don't have direct DB access (e.g. on-call from mobile);
 *   • A new cron job was scheduled and they want to confirm pg_cron
 *     and `cron_run_state` agree on its existence;
 *   • Reviewing whether the `cron-health-monitor` alert pipeline is
 *     itself running (it appears as one of the rows).
 *
 * Query params (all optional):
 *   - `severity_min` ∈ {ok|warn|critical|unknown} — drop rows below
 *     the requested severity. Defaults to `ok` (returns everything).
 *
 * Auth: requires platform_admins membership. The underlying RPC is
 * SECURITY DEFINER + service_role only, so unauthenticated callers
 * also receive 401 *before* the service client is even instantiated.
 *
 * Audit: docs/audit/findings/L06-04-pg-cron-jobs-sem-monitoramento-de-execucao.md
 *
 * L17-01 — defense-in-depth: o handler já tem try/catch + envelope
 * canônico, mas o wrapper externo cobre throws do `requirePlatformAdmin`
 * (e.g. supabase auth crash) e propaga x-request-id quando o cliente
 * envia o header.
 */

const QuerySchema = z.object({
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

export const GET = withErrorHandler(_get, "api.platform.cron-health.get");

async function _get(request: NextRequest) {
  const requestId = randomUUID();

  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      { ok: false, error: { code: "UNAUTHORIZED", message: auth.error, request_id: requestId } },
      { status: auth.status },
    );
  }

  // Parse + validate query params (default-deny: anything outside the
  // enum is rejected with 400 so we never run the RPC on user-supplied
  // junk that could have been intended as a SQL injection probe).
  const parsed = QuerySchema.safeParse({
    severity_min: request.nextUrl.searchParams.get("severity_min") ?? undefined,
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

  // Default to `ok` (i.e. no filter) so the admin grid renders every
  // job. Alert dashboards can pass `severity_min=warn` to focus on
  // the actionable subset.
  const minSeverity: CronSeverity = parsed.data.severity_min ?? "ok";

  try {
    const summary = await checkCronHealth({ minSeverity });

    metrics.gauge(
      "cron_health.total_jobs",
      summary.rows.length,
    );
    metrics.gauge(
      "cron_health.unhealthy_jobs",
      summary.countsBySeverity.warn + summary.countsBySeverity.critical,
    );
    metrics.gauge(
      "cron_health.critical_jobs",
      summary.countsBySeverity.critical,
    );
    metrics.gauge(
      "cron_health.healthy",
      summary.healthy ? 1 : 0,
    );

    return NextResponse.json({
      ok: true,
      healthy: summary.healthy,
      counts: summary.countsBySeverity,
      jobs: summary.rows,
      checked_at: summary.checkedAt,
      request_id: requestId,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    logger.error("platform.cron_health.check_failed", {
      request_id: requestId,
      error: msg,
    });
    metrics.increment("cron_health.check_error");
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "CRON_HEALTH_CHECK_FAILED",
          message: msg,
          request_id: requestId,
        },
      },
      { status: 500 },
    );
  }
}
