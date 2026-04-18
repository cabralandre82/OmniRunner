import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * consent-record — Supabase Edge Function (L04-03 LGPD Art. 7/8)
 *
 * Registra grant/revoke de consentimento do usuário autenticado. Source
 * canônico para o mobile app (Flutter) que não usa o portal Next.js.
 *
 * POST /consent-record
 * Headers: Authorization: Bearer <jwt>
 * Body JSON:
 *   { action: "grant" | "revoke" | "status",
 *     consent_type: "terms" | "privacy" | "health_data" | "location_tracking"
 *                 | "marketing" | "third_party_strava"
 *                 | "third_party_trainingpeaks" | "coach_data_share",
 *     version?: string  // obrigatório para action=grant
 *   }
 *
 * Respostas:
 *   200 { ok:true, event_id, consent_type, version, action, at }   — grant
 *   200 { ok:true, consent_type, action:"revoked", at, no_op? }    — revoke
 *   200 { ok:true, status: [...] }                                 — status
 *   400 { ok:false, code:"INVALID_CONSENT_TYPE"|"MISSING_VERSION"|... }
 *   401/403                                                         — unauth
 *   429 rate-limit                                                  — abuse
 */

const FN = "consent-record";

const VALID_TYPES = new Set([
  "terms",
  "privacy",
  "health_data",
  "location_tracking",
  "marketing",
  "third_party_strava",
  "third_party_trainingpeaks",
  "coach_data_share",
]);

const VALID_ACTIONS = new Set(["grant", "revoke", "status"]);

function getClientIp(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0]?.trim() || null;
  return req.headers.get("x-real-ip") || null;
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === "GET" && new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", version: "1.0.0" }), {
      headers: { "Content-Type": "application/json" },
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

    const rl = await checkRateLimit(
      db,
      user.id,
      { fn: FN, maxRequests: 60, windowSeconds: 60 },
      requestId,
    );
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    let body: Record<string, unknown>;
    try {
      body = (await req.json()) as Record<string, unknown>;
    } catch {
      status = 400;
      errorCode = "INVALID_JSON";
      return jsonErr(400, "INVALID_JSON", "Body must be valid JSON", requestId);
    }

    const action = String(body.action ?? "").toLowerCase();
    if (!VALID_ACTIONS.has(action)) {
      status = 400;
      errorCode = "INVALID_ACTION";
      return jsonErr(
        400,
        "INVALID_ACTION",
        "action must be grant, revoke or status",
        requestId,
      );
    }

    // ── status ──
    if (action === "status") {
      const { data, error } = await db.rpc("fn_consent_status");
      if (error) {
        const c = classifyError(error);
        status = c.httpStatus;
        errorCode = c.code;
        return jsonErr(c.httpStatus, c.code, c.message, requestId);
      }
      return jsonOk({ status: data ?? [] }, requestId);
    }

    const consentType = String(body.consent_type ?? "");
    if (!VALID_TYPES.has(consentType)) {
      status = 400;
      errorCode = "INVALID_CONSENT_TYPE";
      return jsonErr(
        400,
        "INVALID_CONSENT_TYPE",
        `consent_type must be one of ${[...VALID_TYPES].join(", ")}`,
        requestId,
      );
    }

    if (action === "grant") {
      const version = String(body.version ?? "").trim();
      if (!version) {
        status = 400;
        errorCode = "MISSING_VERSION";
        return jsonErr(400, "MISSING_VERSION", "version is required for grant", requestId);
      }
      const { data, error } = await db.rpc("fn_consent_grant", {
        p_consent_type: consentType,
        p_version: version,
        p_source: "mobile",
        p_ip: getClientIp(req),
        p_user_agent: req.headers.get("user-agent"),
        p_request_id: requestId,
      });
      if (error) {
        const c = classifyError(error);
        status = c.httpStatus;
        errorCode = c.code;
        return jsonErr(c.httpStatus, c.code, c.message, requestId);
      }
      return jsonOk({ result: data }, requestId);
    }

    // action === "revoke"
    const { data, error } = await db.rpc("fn_consent_revoke", {
      p_consent_type: consentType,
      p_source: "mobile",
      p_request_id: requestId,
    });
    if (error) {
      const c = classifyError(error);
      status = c.httpStatus;
      errorCode = c.code;
      return jsonErr(c.httpStatus, c.code, c.message, requestId);
    }
    return jsonOk({ result: data }, requestId);
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
