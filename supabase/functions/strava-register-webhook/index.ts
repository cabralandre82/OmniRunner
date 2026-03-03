import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
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
  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '1.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (req.method !== "POST") {
    return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST");
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
  const listRes = await fetch(
    `https://www.strava.com/api/v3/push_subscriptions?client_id=${clientId}&client_secret=${clientSecret}`,
  );
  const existing = await listRes.json();

  if (Array.isArray(existing) && existing.length > 0) {
    return jsonOk({
      message: "Subscription already exists",
      subscription: existing[0],
    });
  }

  // Create new subscription
  const createRes = await fetch("https://www.strava.com/api/v3/push_subscriptions", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      callback_url: callbackUrl,
      verify_token: verifyToken,
    }),
  });

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
