import { NextRequest } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { logger } from "@/lib/logger";
import {
  apiError,
  apiUnauthorized,
  apiValidationFailed,
  apiOk,
} from "@/lib/api/errors";

/**
 * GET /api/platform/analytics/group-overview — L23-07 coach analytics.
 *
 * Surfaces the four coach-facing cuts a group-lead needs to triage
 * training load:
 *
 *   - volume_distribution:    weekly km per athlete, sorted desc
 *   - overtraining:           athletes whose last-7d km exceeds 1.5×
 *                             their window mean (attrition precursor)
 *   - attrition_risk:         athletes with 0 sessions in window or
 *                             last session > 14 days ago
 *   - collective_progress:    window km vs previous-window km + delta%
 *
 * Auth: caller MUST be a coach or assistant of the group. The RPC
 * `fn_group_analytics_overview` enforces this via coaching_members;
 * the route is gated on `supabase.auth.getUser()` for a friendly
 * early 401. window_days is clamped to [7, 180] server-side.
 *
 * Query params:
 *   - group_id     required, uuid
 *   - window_days  optional, integer in [7, 180], default 28
 *
 * Response: `{ ok: true, data: { overview: ... } }`.
 *
 * See docs/runbooks/GROUP_ANALYTICS_RUNBOOK.md.
 */
function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function GET(req: NextRequest) {
  try {
    const params = req.nextUrl.searchParams;

    const groupId = params.get("group_id");
    if (!groupId || !UUID_RE.test(groupId)) {
      return apiValidationFailed(req, "group_id must be a uuid.");
    }

    const windowDaysRaw = params.get("window_days");
    let windowDays = 28;
    if (windowDaysRaw !== null && windowDaysRaw !== "") {
      const n = Number(windowDaysRaw);
      if (!Number.isFinite(n) || !Number.isInteger(n)) {
        return apiValidationFailed(req, "window_days must be an integer.");
      }
      windowDays = n;
    }

    const supabase = createClient();
    const {
      data: { user },
      error: authErr,
    } = await supabase.auth.getUser();
    if (authErr || !user) return apiUnauthorized(req);

    const { data, error } = await supabase.rpc("fn_group_analytics_overview", {
      p_group_id: groupId,
      p_window_days: windowDays,
    });

    if (error) {
      if (error.message && error.message.includes("UNAUTHORIZED")) {
        return apiUnauthorized(req);
      }
      logger.error("GET /api/platform/analytics/group-overview — RPC", error);
      return apiError(req, "DB_ERROR", error.message, 500);
    }

    return apiOk({ overview: data });
  } catch (err) {
    logger.error("GET /api/platform/analytics/group-overview", err);
    return apiError(req, "INTERNAL_ERROR", "unexpected error", 500);
  }
}
