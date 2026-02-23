import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-participant-list — Supabase Edge Function
 *
 * Lists participants of a championship, optionally filtered by group or status.
 * Includes badge info (has_badge, badge_expires_at) for requires_badge championships.
 *
 * POST /champ-participant-list
 * Body: { championship_id, group_id?, status? }
 */

const FN = "champ-participant-list";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let userId: string | null = null;
  let httpStatus = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      httpStatus = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Auth ──────────────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let db: any;
    let user: { id: string; [key: string]: unknown };
    try {
      const auth = await requireUser(req);
      user = auth.user;
      db = auth.db;
      userId = user.id;
    } catch (e) {
      errorCode = "AUTH_ERROR";
      if (e instanceof AuthError) {
        httpStatus = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      httpStatus = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ──────────────────────────────────────────────────
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 60, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      httpStatus = rl.status!;
      if (httpStatus >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body ───────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["championship_id"]);
    } catch (e) {
      httpStatus = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { championship_id, group_id, status: filterStatus } = body;

    // ── 3. Verify championship exists and is visible ────────────────────
    const { data: champ } = await db
      .from("championships")
      .select("id, status, requires_badge")
      .eq("id", championship_id)
      .in("status", ["draft", "open", "active", "completed"])
      .maybeSingle();

    if (!champ) {
      httpStatus = 404;
      return jsonErr(404, "NOT_FOUND", "Championship not found or not visible", requestId);
    }

    // ── 4. Query participants ───────────────────────────────────────────
    let query = db
      .from("championship_participants")
      .select("id, user_id, group_id, status, progress_value, final_rank, joined_at")
      .eq("championship_id", championship_id)
      .order("progress_value", { ascending: false })
      .limit(500);

    if (group_id) {
      query = query.eq("group_id", group_id);
    }
    if (filterStatus) {
      query = query.eq("status", filterStatus);
    }

    const { data: participants, error } = await query;

    if (error) {
      const classified = classifyError(error);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── 5. Enrich with display names and badge info ─────────────────────
    const partList = participants ?? [];
    const userIds = partList.map((p: { user_id: string }) => p.user_id);

    // deno-lint-ignore no-explicit-any
    let profileMap = new Map<string, any>();
    // deno-lint-ignore no-explicit-any
    let badgeMap = new Map<string, any>();

    if (userIds.length > 0) {
      const { data: profiles } = await db
        .from("profiles")
        .select("id, display_name, avatar_url")
        .in("id", userIds);

      for (const p of (profiles ?? [])) {
        profileMap.set(p.id, p);
      }

      if (champ.requires_badge) {
        const { data: badges } = await db
          .from("championship_badges")
          .select("user_id, expires_at")
          .eq("championship_id", championship_id)
          .in("user_id", userIds);

        for (const b of (badges ?? [])) {
          badgeMap.set(b.user_id, b);
        }
      }
    }

    const enriched = partList.map((p: Record<string, unknown>) => {
      const prof = profileMap.get(p.user_id as string);
      const badge = badgeMap.get(p.user_id as string);
      return {
        ...p,
        display_name: prof?.display_name ?? null,
        avatar_url: prof?.avatar_url ?? null,
        has_badge: badge != null,
        badge_expires_at: badge?.expires_at ?? null,
      };
    });

    return jsonOk({
      championship_id,
      participants: enriched,
      count: enriched.length,
    }, requestId);
  } catch (_err) {
    httpStatus = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status: httpStatus, duration_ms: elapsed() });
    }
  }
});
