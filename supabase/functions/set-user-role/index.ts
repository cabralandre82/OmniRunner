import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * set-user-role — Supabase Edge Function
 *
 * Sets the user's self-declared role during onboarding and advances
 * onboarding_state to ROLE_SELECTED.
 *
 * POST /set-user-role
 * Headers: Authorization: Bearer <jwt>
 * Body: { "role": "ATLETA" | "ASSESSORIA_STAFF" }
 *
 * Rules:
 *   - Allowed when onboarding_state is NEW or ROLE_SELECTED
 *   - Denied when onboarding_state is READY (onboarding already completed)
 *   - Updates user_role and sets onboarding_state = ROLE_SELECTED
 *   - Idempotent: calling with the same role while ROLE_SELECTED is a no-op
 */

const FN = "set-user-role";
const VALID_ROLES = ["ATLETA", "ASSESSORIA_STAFF"];
const MUTABLE_STATES = ["NEW", "ROLE_SELECTED"];

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '2.0.0' }), {
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

    // ── 2. Parse + validate body ────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["role"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { role } = body;

    if (!VALID_ROLES.includes(role)) {
      status = 400;
      return jsonErr(400, "INVALID_ROLE", `role must be one of: ${VALID_ROLES.join(", ")}`, requestId);
    }

    // ── 3. Fetch current profile ────────────────────────────────────────
    const { data: profile, error: fetchError } = await db
      .from("profiles")
      .select("onboarding_state, user_role")
      .eq("id", user.id)
      .maybeSingle();

    if (fetchError) {
      const classified = classifyError(fetchError);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!profile) {
      status = 404;
      return jsonErr(404, "PROFILE_NOT_FOUND", "Profile does not exist. Call complete-social-profile first.", requestId);
    }

    // ── 4. Guard: only NEW or ROLE_SELECTED can change role ─────────────
    if (!MUTABLE_STATES.includes(profile.onboarding_state)) {
      status = 409;
      return jsonErr(
        409,
        "ONBOARDING_LOCKED",
        `Cannot change role when onboarding_state is ${profile.onboarding_state}`,
        requestId,
      );
    }

    // ── 5. Update profile ───────────────────────────────────────────────
    const { data: updated, error: updateError } = await db
      .from("profiles")
      .update({
        user_role: role,
        onboarding_state: "ROLE_SELECTED",
        updated_at: new Date().toISOString(),
      })
      .eq("id", user.id)
      .select("id, display_name, onboarding_state, user_role, created_via")
      .single();

    if (updateError) {
      const classified = classifyError(updateError);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk(
      {
        profile: {
          id: updated.id,
          display_name: updated.display_name,
          onboarding_state: updated.onboarding_state,
          user_role: updated.user_role,
          created_via: updated.created_via,
        },
      },
      requestId,
    );
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
