import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * complete-social-profile — Supabase Edge Function
 *
 * Ensures a profile row exists for the authenticated user (idempotent upsert).
 * Sets `created_via` based on the auth provider. Does NOT touch
 * `onboarding_state` or `user_role` — those are handled by later steps.
 *
 * POST /complete-social-profile
 * Headers: Authorization: Bearer <jwt>
 * Body: {} (empty or omitted)
 *
 * Idempotency: calling multiple times is safe — the profile is created once,
 * subsequent calls return the existing profile unchanged.
 */

const FN = "complete-social-profile";

function detectProvider(user: { id: string; [key: string]: unknown }): string {
  const meta = user.app_metadata as Record<string, unknown> | undefined;
  const provider = (meta?.provider as string) ?? "";

  switch (provider) {
    case "google":
      return "OAUTH_GOOGLE";
    case "apple":
      return "OAUTH_APPLE";
    case "facebook":
      return "OAUTH_INSTAGRAM";
    case "email":
      return "EMAIL";
    default: {
      const isAnon = (user as Record<string, unknown>).is_anonymous;
      return isAnon ? "ANON" : "OTHER";
    }
  }
}

function extractDisplayName(user: { id: string; [key: string]: unknown }): string {
  const meta = user.user_metadata as Record<string, unknown> | undefined;
  let name =
    (meta?.full_name as string) ??
    (meta?.name as string) ??
    null;

  if (!name || name.includes("@")) {
    const email = (user as Record<string, unknown>).email as string | undefined;
    if (email) {
      const local = email.split("@")[0];
      name = local.charAt(0).toUpperCase() + local.slice(1);
    } else {
      name = "Runner";
    }
  }

  return name;
}

function extractAvatarUrl(user: { id: string; [key: string]: unknown }): string | null {
  const meta = user.user_metadata as Record<string, unknown> | undefined;
  return (meta?.avatar_url as string) ?? null;
}

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
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Detect provider + metadata ───────────────────────────────────
    const createdVia = detectProvider(user);
    const displayName = extractDisplayName(user);
    const avatarUrl = extractAvatarUrl(user);

    // ── 3. Upsert profile (idempotent) ──────────────────────────────────
    const { data: profile, error: upsertError } = await db
      .from("profiles")
      .upsert(
        {
          id: user.id,
          display_name: displayName,
          avatar_url: avatarUrl,
          created_via: createdVia,
        },
        {
          onConflict: "id",
          ignoreDuplicates: false,
        },
      )
      .select("id, display_name, avatar_url, onboarding_state, user_role, created_via")
      .single();

    if (upsertError) {
      const classified = classifyError(upsertError);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk(
      {
        profile: {
          id: profile.id,
          display_name: profile.display_name,
          avatar_url: profile.avatar_url,
          onboarding_state: profile.onboarding_state,
          user_role: profile.user_role,
          created_via: profile.created_via,
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
