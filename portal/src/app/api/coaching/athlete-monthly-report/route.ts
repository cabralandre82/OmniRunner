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
 * L23-11 — Athlete monthly report (coach surface).
 *
 * GET  /api/coaching/athlete-monthly-report?group_id&user_id&month
 *   Returns the computed monthly metrics + the stored coach notes
 *   (if any), ready to hand off to the PDF renderer (follow-up
 *   L23-11-pdf). `month` is optional; defaults to the current month.
 *
 * PUT  /api/coaching/athlete-monthly-report
 *   Upserts the coach free-text fields (highlights, improvements,
 *   personal_note). Body is JSON:
 *     { group_id, user_id, month, highlights?, improvements?,
 *       personal_note? }
 *   When all three fields are non-empty, the RPC sets `approved_at`
 *   server-side as the explicit coach-ready signal.
 *
 * Auth: `supabase.auth.getUser()` is the friendly early 401. The
 * RPC re-enforces coach/assistant membership; athlete-not-in-group
 * is its own 401 path (we collapse to `UNAUTHORIZED` to avoid
 * leaking membership maps to unrelated callers).
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
const MONTH_RE = /^\d{4}-\d{2}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_TEXT_LEN = 2048;

function monthParamToDate(raw: string | null): string | null {
  if (!raw) return null;
  if (MONTH_RE.test(raw)) return `${raw}-01`;
  if (DATE_RE.test(raw)) return raw.slice(0, 8) + "01";
  return null;
}

function mapRpcAuthError(message: string | undefined): string | null {
  if (!message) return null;
  if (message.includes("UNAUTHORIZED")) return "UNAUTHORIZED";
  if (message.includes("ATHLETE_NOT_IN_GROUP")) return "UNAUTHORIZED";
  return null;
}

export async function GET(req: NextRequest) {
  try {
    const params = req.nextUrl.searchParams;

    const groupId = params.get("group_id");
    if (!groupId || !UUID_RE.test(groupId)) {
      return apiValidationFailed(req, "group_id must be a uuid.");
    }
    const userId = params.get("user_id");
    if (!userId || !UUID_RE.test(userId)) {
      return apiValidationFailed(req, "user_id must be a uuid.");
    }
    const monthRaw = params.get("month");
    const monthStart = monthRaw ? monthParamToDate(monthRaw) : null;
    if (monthRaw && !monthStart) {
      return apiValidationFailed(req, "month must be YYYY-MM or YYYY-MM-DD.");
    }

    const supabase = createClient();
    const {
      data: { user },
      error: authErr,
    } = await supabase.auth.getUser();
    if (authErr || !user) return apiUnauthorized(req);

    const { data, error } = await supabase.rpc("fn_athlete_monthly_report", {
      p_group_id: groupId,
      p_user_id: userId,
      p_month_start: monthStart,
    });

    if (error) {
      if (mapRpcAuthError(error.message) === "UNAUTHORIZED") {
        return apiUnauthorized(req);
      }
      logger.error("GET /api/coaching/athlete-monthly-report — RPC", error);
      return apiError(req, "DB_ERROR", error.message, 500);
    }

    return apiOk({ report: data });
  } catch (err) {
    logger.error("GET /api/coaching/athlete-monthly-report", err);
    return apiError(req, "INTERNAL_ERROR", "unexpected error", 500);
  }
}

export async function PUT(req: NextRequest) {
  try {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return apiValidationFailed(req, "Body must be JSON.");
    }
    if (!body || typeof body !== "object") {
      return apiValidationFailed(req, "Body must be a JSON object.");
    }
    const b = body as Record<string, unknown>;

    const groupId = typeof b.group_id === "string" ? b.group_id : null;
    if (!groupId || !UUID_RE.test(groupId)) {
      return apiValidationFailed(req, "group_id must be a uuid.");
    }
    const userId = typeof b.user_id === "string" ? b.user_id : null;
    if (!userId || !UUID_RE.test(userId)) {
      return apiValidationFailed(req, "user_id must be a uuid.");
    }
    const monthRaw = typeof b.month === "string" ? b.month : null;
    const monthStart = monthParamToDate(monthRaw);
    if (!monthStart) {
      return apiValidationFailed(req, "month must be YYYY-MM or YYYY-MM-DD.");
    }

    const readText = (key: string): string | null => {
      const v = b[key];
      if (v === undefined || v === null) return null;
      if (typeof v !== "string") return null;
      if (v.length > MAX_TEXT_LEN) return null;
      return v;
    };
    const highlights = readText("highlights");
    const improvements = readText("improvements");
    const personalNote = readText("personal_note");

    if (
      (b.highlights !== undefined && b.highlights !== null && highlights === null) ||
      (b.improvements !== undefined && b.improvements !== null && improvements === null) ||
      (b.personal_note !== undefined && b.personal_note !== null && personalNote === null)
    ) {
      return apiValidationFailed(
        req,
        `Text fields must be strings ≤${MAX_TEXT_LEN} chars.`,
      );
    }

    const supabase = createClient();
    const {
      data: { user },
      error: authErr,
    } = await supabase.auth.getUser();
    if (authErr || !user) return apiUnauthorized(req);

    const { data, error } = await supabase.rpc("fn_upsert_monthly_note", {
      p_group_id: groupId,
      p_user_id: userId,
      p_month_start: monthStart,
      p_highlights: highlights,
      p_improvements: improvements,
      p_personal_note: personalNote,
    });

    if (error) {
      if (mapRpcAuthError(error.message) === "UNAUTHORIZED") {
        return apiUnauthorized(req);
      }
      logger.error("PUT /api/coaching/athlete-monthly-report — RPC", error);
      return apiError(req, "DB_ERROR", error.message, 500);
    }

    return apiOk({ note: data });
  } catch (err) {
    logger.error("PUT /api/coaching/athlete-monthly-report", err);
    return apiError(req, "INTERNAL_ERROR", "unexpected error", 500);
  }
}
