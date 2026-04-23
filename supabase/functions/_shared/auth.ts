import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Shared JWT validation helper for Supabase Edge Functions.
 *
 * Workaround for ES256 tokens rejected by the gateway's verify_jwt.
 * Each function sets verify_jwt = false in config.toml and calls
 * requireUser() to validate the JWT manually via auth.getUser().
 *
 * [L10-07] In addition to `auth.getUser`, `requireUser` now enforces
 * zero-trust claims validation against the JWT payload:
 *   - `iss` must match one of the expected issuers (env
 *     AUTH_JWT_EXPECTED_ISSUERS, comma-separated; defaults to
 *     `${SUPABASE_URL}/auth/v1`).
 *   - `aud` must intersect with the allowed audiences (env
 *     AUTH_JWT_ALLOWED_AUDIENCES, comma-separated; defaults to
 *     `authenticated`). Handlers can tighten further via
 *     `opts.allowedAudiences`.
 *   - Optional client pinning via `x-omni-client` header and
 *     `opts.allowedClients` (values: mobile | portal | staff |
 *     platform_admin | internal). This lets high-value routes
 *     (custody/withdraw, platform admin) reject JWTs coming from a
 *     client surface they do not serve.
 *
 * Both iss/aud checks are fail-closed but fully observable: violations
 * throw `AuthError` with status 403 and a machine-readable reason.
 */

export interface AuthResult {
  user: { id: string; [key: string]: unknown };
  /** User-scoped client — respects RLS via the user's JWT. */
  db: SupabaseClient;
  /** Service-role client — bypasses RLS. Use only for admin ops (e.g. auth.admin). */
  adminDb: SupabaseClient;
  supabaseUrl: string;
  serviceKey: string;
  /** Decoded JWT claims (iss/aud/sub/exp/…). Read-only convenience. */
  claims: Record<string, unknown>;
  /** Client surface declared via `x-omni-client` header (lower-cased), or null. */
  client: string | null;
}

export class AuthError extends Error {
  status: number;
  /** Machine-readable reason code (`invalid_issuer`, `audience_mismatch`, …). */
  reason?: string;
  constructor(message: string, status: number, reason?: string) {
    super(message);
    this.name = "AuthError";
    this.status = status;
    this.reason = reason;
  }
}

export interface RequireUserOptions {
  /**
   * Tighten the `aud` claim whitelist for this specific route. If
   * provided, replaces (not extends) the env default.
   */
  allowedAudiences?: string[];
  /**
   * Pin the request to specific client surfaces. The caller must send
   * `x-omni-client: <value>` with a value in the list; otherwise the
   * request is rejected with 403 `client_mismatch`.
   */
  allowedClients?: Array<
    "mobile" | "portal" | "staff" | "platform_admin" | "internal"
  >;
  /**
   * Escape hatch for legacy tokens (pre-L10-07 rollout). Should be set
   * ONLY when investigating a regression and must never ship to prod.
   */
  skipClaimsCheck?: boolean;
}

export function getBearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice(7).trim();
  return token.length > 0 ? token : null;
}

function base64UrlDecode(input: string): string {
  let b64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4;
  if (pad) b64 += "=".repeat(4 - pad);
  if (typeof atob === "function") return atob(b64);
  // Fallback for runtimes without atob.
  return Buffer.from(b64, "base64").toString("binary");
}

/** Decode (but does NOT verify signature) the JWT payload. */
export function decodeJwtPayload(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new AuthError("Malformed JWT", 401, "malformed_jwt");
  try {
    const raw = base64UrlDecode(parts[1]);
    const utf8 = decodeURIComponent(
      Array.prototype.map
        .call(raw, (c: string) => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2))
        .join(""),
    );
    return JSON.parse(utf8);
  } catch {
    throw new AuthError("Cannot decode JWT payload", 401, "malformed_jwt");
  }
}

function splitEnvList(v: string | undefined): string[] {
  return (v ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

function expectedIssuers(supabaseUrl: string): string[] {
  const override = splitEnvList(
    (globalThis as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env.get(
      "AUTH_JWT_EXPECTED_ISSUERS",
    ),
  );
  if (override.length > 0) return override;
  return [`${supabaseUrl.replace(/\/$/, "")}/auth/v1`];
}

function defaultAllowedAudiences(): string[] {
  const override = splitEnvList(
    (globalThis as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env.get(
      "AUTH_JWT_ALLOWED_AUDIENCES",
    ),
  );
  return override.length > 0 ? override : ["authenticated"];
}

/**
 * Validates iss/aud on the decoded claims. Throws AuthError(403) with a
 * machine-readable reason when the check fails.
 */
export function assertClaimsShape(
  claims: Record<string, unknown>,
  opts: { expectedIssuers: string[]; allowedAudiences: string[] },
): void {
  const iss = typeof claims.iss === "string" ? claims.iss : null;
  if (!iss || !opts.expectedIssuers.includes(iss)) {
    throw new AuthError(
      `Invalid JWT issuer${iss ? `: ${iss}` : ""}`,
      403,
      "invalid_issuer",
    );
  }

  const aud = claims.aud;
  const audList: string[] = Array.isArray(aud)
    ? (aud.filter((x) => typeof x === "string") as string[])
    : typeof aud === "string"
      ? [aud]
      : [];
  if (audList.length === 0) {
    throw new AuthError("JWT missing audience claim", 403, "missing_audience");
  }
  const intersects = audList.some((a) => opts.allowedAudiences.includes(a));
  if (!intersects) {
    throw new AuthError(
      `JWT audience not allowed: ${audList.join(",")}`,
      403,
      "audience_mismatch",
    );
  }
}

function pickClient(req: Request): string | null {
  const raw = req.headers.get("x-omni-client") ?? req.headers.get("x-omnirunner-client");
  if (!raw) return null;
  return raw.toLowerCase().trim();
}

/**
 * Extracts and validates the JWT from the request, then returns
 * the authenticated user, a user-scoped DB client (respects RLS),
 * and a service-role admin client (for admin-only operations).
 *
 * Throws AuthError on failure (caller should catch and return json).
 */
export async function requireUser(
  req: Request,
  opts: RequireUserOptions = {},
): Promise<AuthResult> {
  const jwt = getBearerToken(req);
  if (!jwt) {
    throw new AuthError(
      "Missing or malformed Authorization header",
      401,
      "missing_bearer",
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (!supabaseUrl || !serviceKey) {
    throw new AuthError("Server misconfiguration", 500, "missing_env");
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
      isConnectionError ? "auth_service_unavailable" : "invalid_jwt",
    );
  }

  const claims = decodeJwtPayload(jwt);

  if (!opts.skipClaimsCheck) {
    const allowedAudiences =
      opts.allowedAudiences && opts.allowedAudiences.length > 0
        ? opts.allowedAudiences
        : defaultAllowedAudiences();
    assertClaimsShape(claims, {
      expectedIssuers: expectedIssuers(supabaseUrl),
      allowedAudiences,
    });
  }

  const client = pickClient(req);
  if (opts.allowedClients && opts.allowedClients.length > 0) {
    if (!client || !(opts.allowedClients as string[]).includes(client)) {
      throw new AuthError(
        `Client '${client ?? "<unset>"}' not allowed for this route`,
        403,
        "client_mismatch",
      );
    }
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
    claims,
    client,
  };
}
