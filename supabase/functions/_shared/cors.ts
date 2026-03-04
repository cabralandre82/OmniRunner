/**
 * CORS headers and preflight handler for Supabase Edge Functions.
 *
 * Allowed origins are read from CORS_ALLOWED_ORIGINS env var (comma-separated).
 * Falls back to a safe default list when the env var is not set.
 */

const DEFAULT_ORIGINS = [
  "https://omnirunner.app",
  "https://www.omnirunner.app",
  "https://portal.omnirunner.app",
];

function getAllowedOrigins(): string[] {
  const env = Deno.env.get("CORS_ALLOWED_ORIGINS");
  if (env) {
    return env.split(",").map((o) => o.trim()).filter(Boolean);
  }
  return DEFAULT_ORIGINS;
}

function resolveOrigin(req: Request): string {
  const origin = req.headers.get("Origin") ?? "";
  const allowed = getAllowedOrigins();
  if (allowed.includes(origin)) return origin;
  return allowed[0];
}

export function corsHeaders(req: Request): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": resolveOrigin(req),
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-signature, x-request-id",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

/** @deprecated Use corsHeaders(req) for origin-aware CORS. Kept for backward compat. */
export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": DEFAULT_ORIGINS[0],
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-signature, x-request-id",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

/**
 * Returns a 204 Response for OPTIONS preflight requests, null otherwise.
 * Usage: const cors = handleCors(req); if (cors) return cors;
 */
export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  return null;
}
