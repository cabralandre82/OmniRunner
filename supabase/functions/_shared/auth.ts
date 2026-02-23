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
  db: SupabaseClient;
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
 * the authenticated user and a service-role DB client.
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

  if (!supabaseUrl || !serviceKey) {
    throw new AuthError("Server misconfiguration", 500);
  }

  const authClient = createClient(supabaseUrl, serviceKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });

  const { data: userData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !userData?.user) {
    throw new AuthError(
      `Invalid JWT${authError?.message ? `: ${authError.message}` : ""}`,
      401,
    );
  }

  const db = createClient(supabaseUrl, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });

  return { user: userData.user, db, supabaseUrl, serviceKey };
}
