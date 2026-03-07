import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";

/**
 * strava-register-webhook — One-time setup
 *
 * Registers the Strava Webhook subscription pointing to our strava-webhook
 * Edge Function. Only needs to be called once.
 *
 * POST /strava-register-webhook
 * Body: { "callback_url": "https://<supabase-url>/functions/v1/strava-webhook" }
 *
 * Auth: requires service_role JWT (admin-only operation).
 */

serve(async (req: Request) => {
  const url = new URL(req.url);
  if (url.pathname.endsWith("/health")) {
    return new Response(JSON.stringify({ status: "ok", version: "2.0.0" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (req.method !== "POST") {
    return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST");
  }

  // Auth: service_role key required (admin-only operation)
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
  if (!serviceKey) {
    return jsonErr(500, "CONFIG", "Server misconfiguration");
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (token !== serviceKey) {
    return jsonErr(401, "AUTH", "Service role key required");
  }

  const clientId = Deno.env.get("STRAVA_CLIENT_ID");
  const clientSecret = Deno.env.get("STRAVA_CLIENT_SECRET");
  const verifyToken = Deno.env.get("STRAVA_VERIFY_TOKEN") ?? "omnirunner_strava_verify";

  if (!clientId || !clientSecret) {
    return jsonErr(500, "CONFIG", "STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET required");
  }

  let callbackUrl: string;
  try {
    const body = await req.json();
    callbackUrl = body.callback_url;
    if (!callbackUrl) throw new Error("missing callback_url");
  } catch {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    callbackUrl = `${supabaseUrl}/functions/v1/strava-webhook`;
  }

  // First, check existing subscriptions
  const listCtrl = new AbortController();
  const listTimer = setTimeout(() => listCtrl.abort(), 15_000);
  let listRes: Response;
  try {
    listRes = await fetch(
      `https://www.strava.com/api/v3/push_subscriptions?client_id=${clientId}&client_secret=${clientSecret}`,
      { signal: listCtrl.signal },
    );
  } finally {
    clearTimeout(listTimer);
  }
  const existing = await listRes.json();

  if (Array.isArray(existing) && existing.length > 0) {
    return jsonOk({
      message: "Subscription already exists",
      subscription: existing[0],
    });
  }

  // Create new subscription
  const createCtrl = new AbortController();
  const createTimer = setTimeout(() => createCtrl.abort(), 15_000);
  let createRes: Response;
  try {
    createRes = await fetch("https://www.strava.com/api/v3/push_subscriptions", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        callback_url: callbackUrl,
        verify_token: verifyToken,
      }),
      signal: createCtrl.signal,
    });
  } finally {
    clearTimeout(createTimer);
  }

  const result = await createRes.json();

  if (!createRes.ok) {
    return jsonErr(createRes.status, "STRAVA_ERROR", JSON.stringify(result));
  }

  return jsonOk({
    message: "Webhook subscription created",
    subscription: result,
    callback_url: callbackUrl,
  });
});
