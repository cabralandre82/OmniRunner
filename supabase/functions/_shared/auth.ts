import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Shared JWT validation helper for Supabase Edge Functions.
 *
 * Workaround for ES256 tokens rejected by the gateway's verify_jwt.
 * Each function sets verify_jwt = false in config.toml and calls
 * requireUser() to validate the JWT manually via auth.getUser().
 */

export interface AuthResult {
  user: { id: string; [key: string]: unknown };
  /** User-scoped client — respects RLS via the user's JWT. */
  db: SupabaseClient;
  /** Service-role client — bypasses RLS. Use only for admin ops (e.g. auth.admin). */
  adminDb: SupabaseClient;
  supabaseUrl: string;
  serviceKey: string;
}

export class AuthError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = "AuthError";
    this.status = status;
  }
}

export function getBearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice(7).trim();
  return token.length > 0 ? token : null;
}

/**
 * Extracts and validates the JWT from the request, then returns
 * the authenticated user, a user-scoped DB client (respects RLS),
 * and a service-role admin client (for admin-only operations).
 *
 * Throws AuthError on failure (caller should catch and return json).
 */
export async function requireUser(req: Request): Promise<AuthResult> {
  const jwt = getBearerToken(req);
  if (!jwt) {
    throw new AuthError("Missing or malformed Authorization header", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (!supabaseUrl || !serviceKey) {
    throw new AuthError("Server misconfiguration", 500);
  }

  const verifyClient = createClient(supabaseUrl, serviceKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });

  const { data: userData, error: authError } = await verifyClient.auth.getUser(jwt);
  if (authError || !userData?.user) {
    const msg = authError?.message?.toLowerCase() ?? "";
    const isConnectionError =
      msg.includes("connection") ||
      msg.includes("econnrefused") ||
      msg.includes("timeout") ||
      msg.includes("fetch failed");
    const status = isConnectionError ? 503 : 401;
    throw new AuthError(
      isConnectionError
        ? "Auth service unavailable"
        : `Invalid JWT${authError?.message ? `: ${authError.message}` : ""}`,
      status,
    );
  }

  const db = createClient(supabaseUrl, anonKey || serviceKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });

  let _adminDb: SupabaseClient | null = null;

  return {
    user: userData.user,
    db,
    get adminDb(): SupabaseClient {
      if (!_adminDb) {
        _adminDb = createClient(supabaseUrl, serviceKey, {
          auth: {
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUrl: false,
          },
        });
      }
      return _adminDb;
    },
    supabaseUrl,
    serviceKey,
  };
}
