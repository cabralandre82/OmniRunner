import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-list — Supabase Edge Function
 *
 * Lists championships visible to the caller.
 * Filters: status, host_group_id, participating (only those where caller is enrolled).
 *
 * POST /champ-list
 * Body: { status?: string, host_group_id?: string, participating?: boolean }
 */

const FN = "champ-list";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '1.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

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
    let body: Record<string, any> = {};
    try {
      body = await requireJson(req);
    } catch (e) {
      if (e instanceof ValidationError) {
        httpStatus = 400;
        return jsonErr(400, e.code, e.message, requestId);
      }
    }

    const { status: filterStatus, host_group_id, participating } = body;

    // ── 3. Resolve caller's coaching group (for athlete scoping) ──────
    let callerGroupId: string | null = null;
    if (!host_group_id) {
      const { data: profile } = await db
        .from("profiles")
        .select("active_coaching_group_id")
        .eq("id", user.id)
        .maybeSingle();
      callerGroupId = profile?.active_coaching_group_id ?? null;
    }

    // ── 4. Build query ──────────────────────────────────────────────────
    const selectCols = "id, host_group_id, name, description, metric, requires_badge, start_at, end_at, status, max_participants, created_at";

    let query = db
      .from("championships")
      .select(selectCols)
      .order("start_at", { ascending: false })
      .limit(100);

    if (filterStatus) {
      query = query.eq("status", filterStatus);
    } else if (host_group_id) {
      query = query.in("status", ["draft", "open", "active", "completed"]);
    } else {
      query = query.in("status", ["open", "active", "completed"]);
    }

    if (host_group_id) {
      query = query.eq("host_group_id", host_group_id);
    }

    const { data: championships, error } = await query;

    if (error) {
      const classified = classifyError(error);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    let results = championships ?? [];

    // ── 5. Scope to caller's group when no host_group_id filter ───────
    // Athletes without a group cannot see any championships.
    if (!host_group_id && !callerGroupId) {
      return jsonOk({ championships: [], count: 0 }, requestId);
    }

    if (!host_group_id && callerGroupId) {
      const { data: invites } = await db
        .from("championship_invites")
        .select("championship_id")
        .eq("to_group_id", callerGroupId)
        .eq("status", "accepted");

      const invitedChampIds = new Set(
        (invites ?? []).map((inv: { championship_id: string }) => inv.championship_id),
      );

      // deno-lint-ignore no-explicit-any
      results = results.filter((c: any) =>
        c.host_group_id === callerGroupId || invitedChampIds.has(c.id)
      );
    }

    // ── 6. Filter to only championships where user is participant ─────
    if (participating) {
      const champIds = results.map((c: { id: string }) => c.id);
      if (champIds.length > 0) {
        const { data: participations } = await db
          .from("championship_participants")
          .select("championship_id")
          .eq("user_id", user.id)
          .in("championship_id", champIds);

        const participatingIds = new Set(
          (participations ?? []).map((p: { championship_id: string }) => p.championship_id),
        );
        results = results.filter((c: { id: string }) => participatingIds.has(c.id));
      }
    }

    // ── 7. Enrich results with host group name ────────────────────────
    const hostGroupIds = [...new Set(results.map((c: { host_group_id: string }) => c.host_group_id))];
    // deno-lint-ignore no-explicit-any
    const groupNameMap: Record<string, string> = {};
    if (hostGroupIds.length > 0) {
      const { data: groups } = await db
        .from("coaching_groups")
        .select("id, name")
        .in("id", hostGroupIds);
      for (const g of (groups ?? [])) {
        groupNameMap[g.id] = g.name;
      }
    }

    // deno-lint-ignore no-explicit-any
    const enriched = results.map((c: any) => ({
      ...c,
      host_group_name: groupNameMap[c.host_group_id] ?? null,
    }));

    return jsonOk({ championships: enriched, count: enriched.length }, requestId);
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
