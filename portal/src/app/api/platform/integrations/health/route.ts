import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { metrics } from "@/lib/metrics";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

/**
 * GET /api/platform/integrations/health
 *
 * Returns the L16-06 integration telemetry snapshot that backs the
 * `/platform/integrations` dashboard: connected athlete counts per
 * provider (Strava + TrainingPeaks) and rolling-window aggregates of
 * OAuth / webhook / sync events (total, error rate, p50/p95 latency,
 * breakdown by event type).
 *
 * Query params (all optional):
 *   - `provider` ∈ {strava|trainingpeaks|garmin|polar|coros|suunto|apple_health|google_fit}
 *     — when omitted the payload includes every known provider so
 *     operators can spot cross-provider trends (e.g. a Strava outage
 *     cascading into TrainingPeaks sync failures because both share
 *     upstream session mirroring).
 *   - `window_hours` ∈ [1, 720] — rolling window.  Defaults to 24h.
 *
 * Auth: platform_admin only. Backed by `fn_integration_health_snapshot`
 * which raises 42501/FORBIDDEN if the caller lacks the role, so the
 * route defends in depth with `platform_admins` membership + the RPC
 * check.
 *
 * Audit: docs/audit/findings/L16-06-strava-trainingpeaks-oauth-sem-telemetria-de-uso.md
 */

const QuerySchema = z.object({
  provider: z.enum([
    "strava",
    "trainingpeaks",
    "garmin",
    "polar",
    "coros",
    "suunto",
    "apple_health",
    "google_fit",
  ]).optional(),
  window_hours: z
    .string()
    .transform((v) => Number(v))
    .refine((n) => Number.isFinite(n) && n >= 1 && n <= 720, {
      message: "window_hours must be an integer in [1, 720]",
    })
    .optional(),
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

  return { user, supabase } as const;
}

export const GET = withErrorHandler(_get, "api.platform.integrations.health.get");

async function _get(request: NextRequest) {
  const requestId = randomUUID();

  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      { ok: false, error: { code: "UNAUTHORIZED", message: auth.error, request_id: requestId } },
      { status: auth.status },
    );
  }

  const parsed = QuerySchema.safeParse({
    provider: request.nextUrl.searchParams.get("provider") ?? undefined,
    window_hours: request.nextUrl.searchParams.get("window_hours") ?? undefined,
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

  const { supabase } = auth;
  const windowHours = parsed.data.window_hours ?? 24;
  const provider = parsed.data.provider ?? null;

  try {
    const [snapshot, counts] = await Promise.all([
      supabase.rpc("fn_integration_health_snapshot", {
        p_provider: provider,
        p_window_hours: windowHours,
      }),
      supabase.rpc("fn_integration_connected_counts"),
    ]);

    if (snapshot.error) {
      const isForbidden =
        snapshot.error.code === "42501" ||
        /FORBIDDEN/i.test(snapshot.error.message ?? "");
      return NextResponse.json(
        {
          ok: false,
          error: {
            code: isForbidden ? "FORBIDDEN" : "SNAPSHOT_FAILED",
            message: snapshot.error.message,
            request_id: requestId,
          },
        },
        { status: isForbidden ? 403 : 500 },
      );
    }

    metrics.gauge(
      "integration_health.window_hours",
      windowHours,
    );

    return NextResponse.json({
      ok: true,
      snapshot: snapshot.data,
      connected: counts.error ? null : counts.data,
      window_hours: windowHours,
      request_id: requestId,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    logger.error("platform.integrations.health.check_failed", {
      request_id: requestId,
      error: msg,
    });
    metrics.increment("integration_health.check_error");
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "INTEGRATION_HEALTH_FAILED",
          message: msg,
          request_id: requestId,
        },
      },
      { status: 500 },
    );
  }
}
