import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * send-push — Supabase Edge Function
 *
 * Sends push notifications via FCM HTTP v1 API to one or more users.
 * Called server-side (service_role) — not directly by client apps.
 *
 * POST /send-push
 * Body: {
 *   user_ids: string[],      — target users
 *   title: string,            — notification title
 *   body: string,             — notification body
 *   data?: Record<string, string>  — custom payload
 * }
 *
 * Requires env vars:
 *   - FCM_PROJECT_ID         — Firebase project ID
 *   - FCM_SERVICE_ACCOUNT    — Firebase service account JSON (base64 encoded)
 */

const FN = "send-push";

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
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Verify service-role caller ─────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");

    if (!serviceKey || !supabaseUrl) {
      status = 500;
      errorCode = "CONFIG_ERROR";
      return jsonErr(500, "CONFIG_ERROR", "Server misconfiguration", requestId);
    }

    const bearerToken = authHeader.startsWith("Bearer ")
      ? authHeader.slice(7).trim()
      : "";

    if (bearerToken !== serviceKey) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Service-role only", requestId);
    }

    // ── 2. Parse body ─────────────────────────────────────────────────
    let payload: {
      user_ids: string[];
      title: string;
      body: string;
      data?: Record<string, string>;
    };

    try {
      payload = await req.json();
    } catch {
      status = 400;
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    const { user_ids, title, body: notifBody, data } = payload;

    if (!Array.isArray(user_ids) || user_ids.length === 0) {
      status = 422;
      return jsonErr(422, "MISSING_FIELDS", "user_ids required", requestId);
    }
    if (!title || !notifBody) {
      status = 422;
      return jsonErr(422, "MISSING_FIELDS", "title and body required", requestId);
    }

    // ── 3. Fetch device tokens for target users ──────────────────────
    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const { data: tokens, error: tokenErr } = await db
      .from("device_tokens")
      .select("token, platform")
      .in("user_id", user_ids);

    if (tokenErr) {
      status = 500;
      errorCode = "DB_ERROR";
      return jsonErr(500, "DB_ERROR", "Failed to fetch tokens", requestId);
    }

    if (!tokens || tokens.length === 0) {
      return jsonOk({
        sent: 0,
        skipped: user_ids.length,
        reason: "no_tokens",
      }, requestId);
    }

    // ── 4. Get FCM access token ──────────────────────────────────────
    const fcmProjectId = Deno.env.get("FCM_PROJECT_ID");
    const fcmServiceAccountB64 = Deno.env.get("FCM_SERVICE_ACCOUNT");

    if (!fcmProjectId || !fcmServiceAccountB64) {
      status = 500;
      errorCode = "FCM_NOT_CONFIGURED";
      return jsonErr(500, "FCM_NOT_CONFIGURED", "FCM credentials missing", requestId);
    }

    const accessToken = await getFcmAccessToken(fcmServiceAccountB64);

    // ── 5. Send to device tokens in batches with concurrency cap ─────
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${fcmProjectId}/messages:send`;
    const CONCURRENCY = 10;
    const BATCH_SIZE = 500;
    const DEADLINE_MS = 50_000;
    const fnStart = Date.now();

    let sent = 0;
    let failed = 0;
    let skippedByDeadline = 0;
    const staleTokens: string[] = [];

    function buildMessage(token: string, platform: string): Record<string, unknown> {
      const message: Record<string, unknown> = {
        token,
        notification: { title, body: notifBody },
      };
      if (data) message.data = data;
      if (platform === "android") {
        message.android = {
          priority: "high",
          notification: { channel_id: "omni_runner_default" },
        };
      } else if (platform === "ios") {
        message.apns = {
          payload: { aps: { sound: "default", badge: 1 } },
        };
      }
      return message;
    }

    async function sendOne(token: string, platform: string): Promise<"sent" | "failed" | "stale"> {
      const message = buildMessage(token, platform);
      try {
        const fcmCtrl = new AbortController();
        const fcmTimer = setTimeout(() => fcmCtrl.abort(), 15_000);
        let res: Response;
        try {
          res = await fetch(fcmUrl, {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ message }),
            signal: fcmCtrl.signal,
          });
        } finally {
          clearTimeout(fcmTimer);
        }
        if (res.ok) return "sent";
        const errBody = await res.json().catch(() => ({}));
        const errObj = (errBody as Record<string, unknown>)?.error as Record<string, unknown> | undefined;
        const errorStatus = errObj?.status as string | undefined;
        if (errorStatus === "NOT_FOUND" || errorStatus === "UNREGISTERED") return "stale";
        return "failed";
      } catch {
        return "failed";
      }
    }

    for (let batchStart = 0; batchStart < tokens.length; batchStart += BATCH_SIZE) {
      if (Date.now() - fnStart > DEADLINE_MS) {
        skippedByDeadline = tokens.length - batchStart;
        break;
      }

      const batch = tokens.slice(batchStart, batchStart + BATCH_SIZE);

      // Process batch with concurrency cap
      for (let i = 0; i < batch.length; i += CONCURRENCY) {
        if (Date.now() - fnStart > DEADLINE_MS) {
          skippedByDeadline += batch.length - i;
          break;
        }

        const chunk = batch.slice(i, i + CONCURRENCY);
        const results = await Promise.allSettled(
          chunk.map(({ token, platform }) => sendOne(token, platform)),
        );

        for (let j = 0; j < results.length; j++) {
          const r = results[j];
          if (r.status === "fulfilled") {
            if (r.value === "sent") sent++;
            else if (r.value === "stale") { staleTokens.push(chunk[j].token); failed++; }
            else failed++;
          } else {
            failed++;
          }
        }
      }

      if (skippedByDeadline > 0) break;
    }

    // ── 6. Clean up stale tokens ─────────────────────────────────────
    if (staleTokens.length > 0) {
      await db
        .from("device_tokens")
        .delete()
        .in("token", staleTokens);
    }

    return jsonOk({
      sent,
      failed,
      stale_cleaned: staleTokens.length,
      total_tokens: tokens.length,
      skipped_by_deadline: skippedByDeadline,
    }, requestId);
  } catch (_err) {
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

// ═════════════════════════════════════════════════════════════════════════════
// FCM OAuth2 — Service Account → Access Token
// ═════════════════════════════════════════════════════════════════════════════

async function getFcmAccessToken(serviceAccountB64: string): Promise<string> {
  const saJson = JSON.parse(atob(serviceAccountB64));
  const email = saJson.client_email;
  const privateKeyPem = saJson.private_key;

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = base64url(JSON.stringify(header));
  const encodedClaims = base64url(JSON.stringify(claimSet));
  const signInput = `${encodedHeader}.${encodedClaims}`;

  const key = await importPkcs8(privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(signInput),
  );

  const encodedSig = base64url(
    String.fromCharCode(...new Uint8Array(signature)),
  );
  const jwt = `${signInput}.${encodedSig}`;

  const oauthCtrl = new AbortController();
  const oauthTimer = setTimeout(() => oauthCtrl.abort(), 15_000);
  let res: Response;
  try {
    res = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
      signal: oauthCtrl.signal,
    });
  } finally {
    clearTimeout(oauthTimer);
  }

  if (!res.ok) {
    throw new Error(`OAuth2 token exchange failed: ${res.status}`);
  }

  const tokenData = await res.json() as { access_token: string };
  return tokenData.access_token;
}

async function importPkcs8(pem: string): Promise<CryptoKey> {
  const lines = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(lines), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function base64url(str: string): string {
  return btoa(str)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
