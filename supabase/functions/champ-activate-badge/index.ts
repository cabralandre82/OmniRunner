import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-activate-badge — Supabase Edge Function
 *
 * Athlete scans a QR (nonce) from a CHAMP_BADGE_ACTIVATE intent.
 * Consumes the intent, creates a championship_badge (expires at championship end_at),
 * and enrolls the athlete as a participant.
 *
 * The intent's metadata must include { championship_id }.
 * The intent must have type = CHAMP_BADGE_ACTIVATE and status = OPEN.
 *
 * POST /champ-activate-badge
 * Body: { nonce: string }
 */

const FN = "champ-activate-badge";

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
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
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
        status = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      status = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ──────────────────────────────────────────────────
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 20, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body ───────────────────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await requireJson(req);
      requireFields(body, ["nonce"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const nonce = body.nonce as string;

    // ── 3. Find intent by nonce ─────────────────────────────────────────
    const { data: intent, error: fetchErr } = await db
      .from("token_intents")
      .select("*")
      .eq("nonce", nonce)
      .maybeSingle();

    if (fetchErr) {
      const classified = classifyError(fetchErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!intent) {
      status = 404;
      return jsonErr(404, "INTENT_NOT_FOUND", "No intent with this nonce", requestId);
    }

    if (intent.type !== "CHAMP_BADGE_ACTIVATE") {
      status = 400;
      return jsonErr(400, "WRONG_INTENT_TYPE", "This function only accepts CHAMP_BADGE_ACTIVATE intents", requestId);
    }

    // Idempotent: already consumed — check if badge exists
    if (intent.status === "CONSUMED") {
      const { data: existingBadge } = await db
        .from("championship_badges")
        .select("id, championship_id, expires_at")
        .eq("intent_id", intent.id)
        .eq("user_id", user.id)
        .maybeSingle();

      return jsonOk({
        status: "already_activated",
        intent_id: intent.id,
        badge: existingBadge ?? null,
      }, requestId);
    }

    if (intent.status !== "OPEN") {
      status = 409;
      return jsonErr(409, "INTENT_NOT_OPEN", `Intent status is ${intent.status}`, requestId);
    }

    // Check expiry
    if (Date.now() > new Date(intent.expires_at).getTime()) {
      await db
        .from("token_intents")
        .update({ status: "EXPIRED" })
        .eq("id", intent.id)
        .eq("status", "OPEN");
      status = 410;
      return jsonErr(410, "INTENT_EXPIRED", "This intent has expired", requestId);
    }

    // ── 4. Load championship (from intent metadata or group lookup) ─────
    // Intent for CHAMP_BADGE_ACTIVATE should carry championship_id in nonce
    // convention or we look it up from a related field. We use the
    // token_intents table: the staff who created the intent should have
    // stored championship_id. We'll look for an active championship
    // hosted by the intent's group that requires badges.
    //
    // Strategy: check if intent has target metadata. If not, find the
    // open/active championship hosted by intent.group_id that requires badge.

    // First try: look for championship_id passed in body
    let championshipId = body.championship_id as string | undefined;

    if (!championshipId) {
      // Fallback: find the open/active championship for this group requiring badge
      const { data: champs } = await db
        .from("championships")
        .select("id, end_at")
        .eq("host_group_id", intent.group_id)
        .eq("requires_badge", true)
        .in("status", ["open", "active"])
        .order("start_at", { ascending: true })
        .limit(1);

      if (!champs || champs.length === 0) {
        status = 404;
        return jsonErr(404, "NO_CHAMPIONSHIP", "No open championship requiring badge found for this group", requestId);
      }
      championshipId = champs[0].id;
    }

    // Load championship details
    const { data: champ, error: champErr } = await db
      .from("championships")
      .select("id, host_group_id, end_at, status, requires_badge, max_participants")
      .eq("id", championshipId)
      .maybeSingle();

    if (champErr || !champ) {
      status = 404;
      return jsonErr(404, "CHAMPIONSHIP_NOT_FOUND", "Championship not found", requestId);
    }

    if (!["open", "active"].includes(champ.status)) {
      status = 409;
      return jsonErr(409, "CHAMPIONSHIP_NOT_OPEN", `Championship status is ${champ.status}`, requestId);
    }

    // ── 5. Verify athlete's group has an accepted invite ────────────────
    const { data: profile } = await db
      .from("profiles")
      .select("active_coaching_group_id")
      .eq("id", user.id)
      .maybeSingle();

    const athleteGroupId = profile?.active_coaching_group_id;

    if (!athleteGroupId) {
      status = 403;
      return jsonErr(403, "NO_GROUP", "You must belong to a coaching group", requestId);
    }

    // Host group athletes auto-qualify; others need accepted invite
    if (athleteGroupId !== champ.host_group_id) {
      const { data: invite } = await db
        .from("championship_invites")
        .select("status")
        .eq("championship_id", championshipId)
        .eq("to_group_id", athleteGroupId)
        .eq("status", "accepted")
        .maybeSingle();

      if (!invite) {
        status = 403;
        return jsonErr(403, "GROUP_NOT_INVITED", "Your group has no accepted invite for this championship", requestId);
      }
    }

    // ── 6. Check max participants ───────────────────────────────────────
    if (champ.max_participants != null) {
      const { count } = await db
        .from("championship_participants")
        .select("id", { count: "exact", head: true })
        .eq("championship_id", championshipId)
        .in("status", ["enrolled", "active"]);

      if (count != null && count >= champ.max_participants) {
        status = 409;
        return jsonErr(409, "CHAMPIONSHIP_FULL", "Championship has reached max participants", requestId);
      }
    }

    // ── 7. Consume intent ───────────────────────────────────────────────
    const { data: updated, error: consumeErr } = await db
      .from("token_intents")
      .update({
        status: "CONSUMED",
        target_user_id: user.id,
        consumed_at: new Date().toISOString(),
      })
      .eq("id", intent.id)
      .eq("status", "OPEN")
      .select("id, status")
      .maybeSingle();

    if (consumeErr) {
      const classified = classifyError(consumeErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!updated) {
      return jsonOk({ status: "already_activated", intent_id: intent.id }, requestId);
    }

    // ── 8. Create championship badge (expires at championship end_at) ───
    const { data: badge, error: badgeErr } = await db
      .from("championship_badges")
      .upsert({
        championship_id: championshipId,
        user_id: user.id,
        intent_id: intent.id,
        expires_at: champ.end_at,
      }, { onConflict: "championship_id,user_id" })
      .select("id, championship_id, expires_at")
      .single();

    if (badgeErr) {
      const classified = classifyError(badgeErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── 9. Enroll as participant ────────────────────────────────────────
    const { error: enrollErr } = await db
      .from("championship_participants")
      .upsert({
        championship_id: championshipId,
        user_id: user.id,
        group_id: athleteGroupId,
        status: "enrolled",
      }, { onConflict: "championship_id,user_id" });

    if (enrollErr) {
      const classified = classifyError(enrollErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk({
      status: "activated",
      intent_id: intent.id,
      badge_id: badge.id,
      championship_id: championshipId,
      expires_at: badge.expires_at,
    }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status, duration_ms: elapsed() });
    }
  }
});
