import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * validate-social-login — Supabase Edge Function
 *
 * Handles social login providers not natively supported by Supabase Auth
 * (e.g. TikTok). The app calls this with { provider, action } to initiate
 * the OAuth flow.
 *
 * For now, TikTok login is not yet configured, so we return a clear error
 * rather than crashing. When TikTok OAuth credentials are added, this
 * function will generate the auth_url and handle the callback.
 *
 * Env vars (future):
 *   TIKTOK_CLIENT_KEY
 *   TIKTOK_CLIENT_SECRET
 *   TIKTOK_REDIRECT_URI
 */

const FN = "validate-social-login";

serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;

  if (req.method === "OPTIONS") {
    return jsonOk({}, requestId);
  }

  try {
    let body: { provider?: string; action?: string } = {};
    try {
      body = await req.json();
    } catch {
      status = 400;
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    const provider = body.provider ?? "";
    const action = body.action ?? "";

    if (provider === "tiktok" && action === "init") {
      const clientKey = Deno.env.get("TIKTOK_CLIENT_KEY");
      const redirectUri = Deno.env.get("TIKTOK_REDIRECT_URI");

      if (!clientKey || !redirectUri) {
        return jsonOk({
          ok: false,
          error: "TikTok login is not available yet. Configure TIKTOK_CLIENT_KEY and TIKTOK_REDIRECT_URI.",
        }, requestId);
      }

      const state = crypto.randomUUID();
      const authUrl =
        `https://www.tiktok.com/v2/auth/authorize/` +
        `?client_key=${clientKey}` +
        `&response_type=code` +
        `&scope=user.info.basic` +
        `&redirect_uri=${encodeURIComponent(redirectUri)}` +
        `&state=${state}`;

      return jsonOk({ ok: true, auth_url: authUrl, state }, requestId);
    }

    status = 400;
    return jsonErr(400, "UNSUPPORTED_PROVIDER", `Provider '${provider}' with action '${action}' is not supported`, requestId);

  } catch (err) {
    status = 500;
    logError({
      request_id: requestId,
      fn: FN,
      user_id: null,
      error_code: `INTERNAL: ${(err as Error).message}`,
      duration_ms: elapsed(),
    });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    logRequest({ request_id: requestId, fn: FN, user_id: null, status, duration_ms: elapsed() });
  }
});
