import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { CORS_HEADERS, handleCors } from "../_shared/cors.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { logIntegrationEvent } from "../_shared/integration_telemetry.ts";

const FN = "trainingpeaks-oauth";
const TP_CLIENT_ID = Deno.env.get("TRAININGPEAKS_CLIENT_ID") ?? "";
const TP_CLIENT_SECRET = Deno.env.get("TRAININGPEAKS_CLIENT_SECRET") ?? "";
const TP_REDIRECT_URI = Deno.env.get("TRAININGPEAKS_REDIRECT_URI") ?? "";
const TP_AUTH_URL = "https://oauth.trainingpeaks.com/OAuth/Authorize";
const TP_TOKEN_URL = "https://oauth.trainingpeaks.com/oauth/token";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STATE_SECRET = Deno.env.get("TRAININGPEAKS_STATE_SECRET") ?? SERVICE_KEY;

async function signState(payload: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(STATE_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(payload));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyState(payload: string, receivedHmac: string): Promise<boolean> {
  const expected = await signState(payload);
  if (expected.length !== receivedHmac.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ receivedHmac.charCodeAt(i);
  }
  return diff === 0;
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    const url = new URL(req.url);

    if (url.pathname.endsWith("/health")) {
      return new Response(
        JSON.stringify({ status: "ok", fn: FN }),
        { headers: { ...CORS_HEADERS, "content-type": "application/json" } },
      );
    }

    const flagDb = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: flagRow } = await flagDb
      .from("feature_flags")
      .select("enabled")
      .eq("key", "trainingpeaks_enabled")
      .maybeSingle();
    if (!flagRow?.enabled) {
      status = 403;
      errorCode = "TRAININGPEAKS_DISABLED";
      return jsonErr(403, "TRAININGPEAKS_DISABLED", "TrainingPeaks integration is disabled", requestId);
    }

    const action = url.searchParams.get("action");

    // Step 1: Initiate OAuth — redirect user to TrainingPeaks
    if (action === "authorize") {
      const statePayload = url.searchParams.get("state") ?? "";
      if (!statePayload.includes(":")) {
        status = 400;
        errorCode = "INVALID_STATE";
        return jsonErr(400, "INVALID_STATE", "State must be userId:groupId", requestId);
      }
      const signedState = `${statePayload}:${await signState(statePayload)}`;
      const authUrl =
        `${TP_AUTH_URL}?response_type=code&client_id=${TP_CLIENT_ID}` +
        `&redirect_uri=${encodeURIComponent(TP_REDIRECT_URI)}` +
        `&scope=workouts:read workouts:write athlete:read&state=${encodeURIComponent(signedState)}`;
      const telemetryDb = createClient(SUPABASE_URL, SERVICE_KEY);
      const [tpUserId] = statePayload.split(":");
      await logIntegrationEvent(telemetryDb, {
        provider: "trainingpeaks",
        event_type: "oauth_start",
        status: "success",
        user_id: tpUserId || null,
        metadata: { request_id: requestId },
      });
      return Response.redirect(authUrl, 302);
    }

    // Step 2: Exchange code for token (callback)
    if (action === "callback") {
      const code = url.searchParams.get("code");
      const state = url.searchParams.get("state");

      if (!code || !state) {
        status = 400;
        errorCode = "MISSING_PARAMS";
        return jsonErr(400, "MISSING_PARAMS", "Missing code or state", requestId);
      }

      // state = "userId:groupId:hmac"
      const parts = state.split(":");
      if (parts.length < 3) {
        status = 400;
        errorCode = "INVALID_STATE";
        return jsonErr(400, "INVALID_STATE", "Invalid or tampered state", requestId);
      }
      const receivedHmac = parts.pop()!;
      const statePayload = parts.join(":");
      const valid = await verifyState(statePayload, receivedHmac);
      if (!valid) {
        status = 400;
        errorCode = "INVALID_STATE";
        return jsonErr(400, "INVALID_STATE", "Invalid or tampered state", requestId);
      }
      const [userId, groupId] = parts;

      const tokenCtrl = new AbortController();
      const tokenTimer = setTimeout(() => tokenCtrl.abort(), 15_000);
      let tokenRes: Response;
      try {
        tokenRes = await fetch(TP_TOKEN_URL, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            grant_type: "authorization_code",
            code,
            client_id: TP_CLIENT_ID,
            client_secret: TP_CLIENT_SECRET,
            redirect_uri: TP_REDIRECT_URI,
          }),
          signal: tokenCtrl.signal,
        });
      } finally {
        clearTimeout(tokenTimer);
      }

      if (!tokenRes.ok) {
        status = 502;
        errorCode = "TOKEN_EXCHANGE_FAILED";
        const errText = await tokenRes.text();
        const telemetryDb = createClient(SUPABASE_URL, SERVICE_KEY);
        await logIntegrationEvent(telemetryDb, {
          provider: "trainingpeaks",
          event_type: "oauth_callback_error",
          status: "error",
          user_id: userId || null,
          error_code: `HTTP_${tokenRes.status}`,
          latency_ms: elapsed(),
          metadata: { request_id: requestId },
        });
        return jsonErr(502, "TOKEN_EXCHANGE_FAILED", errText.substring(0, 200), requestId);
      }

      const tokens = await tokenRes.json();
      const accessToken = tokens.access_token;
      const refreshToken = tokens.refresh_token;
      const expiresIn = tokens.expires_in ?? 3600;

      // Get TP athlete profile
      const meCtrl = new AbortController();
      const meTimer = setTimeout(() => meCtrl.abort(), 15_000);
      let meRes: Response;
      try {
        meRes = await fetch("https://api.trainingpeaks.com/v1/athlete/profile", {
          headers: { Authorization: `Bearer ${accessToken}` },
          signal: meCtrl.signal,
        });
      } finally {
        clearTimeout(meTimer);
      }
      const meData = meRes.ok ? await meRes.json() : null;
      const tpUserId = meData?.Id?.toString() ?? null;

      const db = createClient(SUPABASE_URL, SERVICE_KEY);
      const { error: upsertErr } = await db.from("coaching_device_links").upsert(
        {
          athlete_user_id: userId,
          group_id: groupId,
          provider: "trainingpeaks",
          access_token: accessToken,
          refresh_token: refreshToken,
          provider_user_id: tpUserId,
          expires_at: new Date(Date.now() + expiresIn * 1000).toISOString(),
          linked_at: new Date().toISOString(),
        },
        { onConflict: "athlete_user_id,provider" },
      );

      if (upsertErr) {
        status = 500;
        errorCode = "DB_UPSERT_FAILED";
        await logIntegrationEvent(db, {
          provider: "trainingpeaks",
          event_type: "oauth_callback_error",
          status: "error",
          user_id: userId,
          error_code: "DB_UPSERT_FAILED",
          latency_ms: elapsed(),
          metadata: { request_id: requestId },
        });
        return jsonErr(500, "DB_UPSERT_FAILED", upsertErr.message, requestId);
      }

      await logIntegrationEvent(db, {
        provider: "trainingpeaks",
        event_type: "oauth_callback_success",
        status: "success",
        user_id: userId,
        external_id: tpUserId,
        latency_ms: elapsed(),
        metadata: { request_id: requestId, group_id: groupId },
      });

      return new Response(
        `<html><body><h2>TrainingPeaks vinculado com sucesso!</h2><p>Volte ao aplicativo.</p><script>window.close();</script></body></html>`,
        { status: 200, headers: { "content-type": "text/html" } },
      );
    }

    // Step 3: Refresh token
    if (action === "refresh" && req.method === "POST") {
      const { user } = await requireUser(req);

      let body;
      try {
        body = await req.json();
      } catch {
        return jsonErr(400, "INVALID_JSON", "Malformed request body", requestId);
      }
      const { user_id } = body;

      if (!user_id) {
        status = 400;
        errorCode = "MISSING_USER_ID";
        return jsonErr(400, "MISSING_USER_ID", "Missing user_id", requestId);
      }

      if (user_id !== user.id) {
        status = 403;
        errorCode = "FORBIDDEN";
        return jsonErr(403, "FORBIDDEN", "Cannot refresh token for another user", requestId);
      }

      const db = createClient(SUPABASE_URL, SERVICE_KEY);
      const { data: link } = await db
        .from("coaching_device_links")
        .select("refresh_token")
        .eq("athlete_user_id", user_id)
        .eq("provider", "trainingpeaks")
        .maybeSingle();

      if (!link?.refresh_token) {
        status = 404;
        errorCode = "NO_REFRESH_TOKEN";
        return jsonErr(404, "NO_REFRESH_TOKEN", "No refresh token found", requestId);
      }

      const refreshCtrl = new AbortController();
      const refreshTimer = setTimeout(() => refreshCtrl.abort(), 15_000);
      let refreshRes: Response;
      try {
        refreshRes = await fetch(TP_TOKEN_URL, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            grant_type: "refresh_token",
            refresh_token: link.refresh_token,
            client_id: TP_CLIENT_ID,
            client_secret: TP_CLIENT_SECRET,
          }),
          signal: refreshCtrl.signal,
        });
      } finally {
        clearTimeout(refreshTimer);
      }

      if (!refreshRes.ok) {
        status = 502;
        errorCode = "REFRESH_FAILED";
        await logIntegrationEvent(db, {
          provider: "trainingpeaks",
          event_type: "token_refresh_failure",
          status: "error",
          user_id,
          error_code: `HTTP_${refreshRes.status}`,
          latency_ms: elapsed(),
          metadata: { request_id: requestId },
        });
        return jsonErr(502, "REFRESH_FAILED", "Token refresh failed", requestId);
      }

      const newTokens = await refreshRes.json();
      await db
        .from("coaching_device_links")
        .update({
          access_token: newTokens.access_token,
          refresh_token: newTokens.refresh_token ?? link.refresh_token,
          expires_at: new Date(Date.now() + (newTokens.expires_in ?? 3600) * 1000).toISOString(),
        })
        .eq("athlete_user_id", user_id)
        .eq("provider", "trainingpeaks");

      await logIntegrationEvent(db, {
        provider: "trainingpeaks",
        event_type: "token_refresh_success",
        status: "success",
        user_id,
        latency_ms: elapsed(),
        metadata: { request_id: requestId },
      });

      return jsonOk({ refreshed: true }, requestId);
    }

    status = 400;
    errorCode = "UNKNOWN_ACTION";
    return jsonErr(400, "UNKNOWN_ACTION", "Unknown action", requestId);
  } catch (err) {
    if (err instanceof AuthError) {
      status = err.status;
      errorCode = "AUTH";
      return jsonErr(err.status, "AUTH", err.message, requestId);
    }
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: null, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: null, status, duration_ms: elapsed() });
    }
  }
});
