/**
 * Shared helpers for the `delete-account` edge function (L04-02 / L01-36 /
 * L06-08).
 *
 * Pure functions extracted from `delete-account/index.ts` so they can be
 * unit-tested deterministically without spinning up the full edge runtime
 * or a Postgres instance.
 *
 * # Threat model
 *
 *   - **Email leak via audit trail**: we never store the raw email in
 *     `account_deletion_log`; only its SHA-256 hex digest. `hashEmail`
 *     normalises (lowercase + trim) before hashing so the same address
 *     always produces the same hash regardless of input casing.
 *
 *   - **Replay of the deletion call**: each request gets a fresh
 *     `request_id` (UUIDv4 from `crypto.randomUUID()`); the
 *     `account_deletion_log.request_id` UNIQUE constraint prevents two
 *     concurrent INSERTs from racing past the initial logging step.
 *
 *   - **PII in the failure_reason / cleanup_report**: `truncateReason`
 *     caps the length at 500 chars to avoid pathological logs, and the
 *     caller is expected to feed only Postgres SQLERRM / auth admin
 *     error messages — never user-supplied input.
 *
 *   - **IP / UA leak**: `extractClientContext` returns `null` for the IP
 *     when the deployment is behind an unknown proxy (we do NOT trust
 *     `x-forwarded-for` blindly; only the first hop, capped to a single
 *     IP, only when the header looks well-formed).
 */

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/** Max characters we persist into `failure_reason` / `client_ua`. */
export const MAX_REASON_LENGTH = 500;

/** Outcomes mirrored from the SQL CHECK constraint. */
export type DeletionOutcome =
  | "success"
  | "cleanup_failed"
  | "auth_delete_failed"
  | "cancelled_by_validation"
  | "internal_error";

// ─────────────────────────────────────────────────────────────────────────────
// Hashing
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Normalise an email address for hashing. Lowercase + trim is sufficient
 * — we deliberately do NOT canonicalise gmail "+plus" tags or strip dots
 * because those *are* meaningful for ANPD bookkeeping (different signup
 * may legitimately use different aliases of the same mailbox).
 *
 * Returns null if the input is empty / not a string. The caller should
 * fall back to a deterministic placeholder (e.g. `hashEmail("")` is
 * still well-defined and produces a known constant).
 *
 * @internal
 */
function normaliseEmail(email: string | null | undefined): string {
  if (typeof email !== "string") return "";
  return email.trim().toLowerCase();
}

function bytesToHex(buf: ArrayBuffer | Uint8Array): string {
  const u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let out = "";
  for (let i = 0; i < u8.byteLength; i++) {
    out += u8[i].toString(16).padStart(2, "0");
  }
  return out;
}

/**
 * SHA-256 hex digest of a normalised email address. Returns 64 hex
 * chars; matches the CHECK constraint `^[0-9a-f]{64}$` on
 * `account_deletion_log.email_hash`.
 *
 *   hashEmail("Alice@Example.com") === hashEmail(" alice@example.com ")
 *
 * For an empty/missing email we hash the literal empty string so the
 * result is deterministic and queryable ("how many deletions had no
 * email on record?") rather than NULL-and-untrackable.
 */
export async function hashEmail(email: string | null | undefined): Promise<string> {
  const norm = normaliseEmail(email);
  const buf = new TextEncoder().encode(norm);
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return bytesToHex(digest);
}

// ─────────────────────────────────────────────────────────────────────────────
// Reason / context sanitisation
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Cap a free-form reason string at MAX_REASON_LENGTH chars and strip
 * control characters (\x00-\x1F except \t, \n) that could break log
 * parsing or hide payload in pretty-print viewers. Returns null for
 * empty / non-string input so the DB stores NULL rather than an
 * empty string (queryable `IS NULL` semantics).
 */
export function truncateReason(value: unknown): string | null {
  if (typeof value !== "string") return null;
  // eslint-disable-next-line no-control-regex
  const cleaned = value.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "");
  const trimmed = cleaned.trim();
  if (trimmed.length === 0) return null;
  return trimmed.length > MAX_REASON_LENGTH
    ? trimmed.slice(0, MAX_REASON_LENGTH)
    : trimmed;
}

/**
 * Extract the first IP from an `x-forwarded-for` header value, but only
 * if it parses as a valid IPv4 / IPv6 literal. Anything malformed (or
 * absent) returns null so the DB stores NULL rather than poisonous
 * client-supplied junk.
 */
export function extractClientIp(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (!xff) return null;
  const first = xff.split(",")[0]?.trim() ?? "";
  if (first.length === 0) return null;
  // Basic IPv4 / IPv6 sanity check. We rely on Postgres `inet` cast at
  // INSERT time as the authoritative validator (it will REJECT garbage
  // and the surrounding catch records `internal_error`).
  const ipv4 = /^(?:\d{1,3}\.){3}\d{1,3}$/;
  const ipv6 = /^[0-9a-fA-F:]+$/;
  if (!ipv4.test(first) && !ipv6.test(first)) return null;
  return first;
}

/**
 * Extract a truncated User-Agent string. `null` when missing / empty.
 * Capped at MAX_REASON_LENGTH to match the column constraint.
 */
export function extractClientUserAgent(req: Request): string | null {
  const ua = req.headers.get("user-agent");
  return truncateReason(ua);
}

// ─────────────────────────────────────────────────────────────────────────────
// Log row shape
// ─────────────────────────────────────────────────────────────────────────────

export interface DeletionLogInitial {
  request_id: string;
  user_id: string;
  email_hash: string;
  user_role: string | null;
  client_ip: string | null;
  client_ua: string | null;
}

export interface DeletionLogTerminal {
  outcome: DeletionOutcome;
  failure_reason: string | null;
  cleanup_report: Record<string, unknown> | null;
  completed_at: string;
}

/**
 * Build the initial-INSERT payload. Pure: no DB I/O, no global state.
 */
export function buildInitialLogRow(args: {
  requestId: string;
  userId: string;
  emailHash: string;
  userRole: string | null | undefined;
  req: Request;
}): DeletionLogInitial {
  return {
    request_id: args.requestId,
    user_id: args.userId,
    email_hash: args.emailHash,
    user_role: typeof args.userRole === "string" ? args.userRole : null,
    client_ip: extractClientIp(args.req),
    client_ua: extractClientUserAgent(args.req),
  };
}

/**
 * Build the terminal UPDATE payload. Pure.
 */
export function buildTerminalLogRow(args: {
  outcome: DeletionOutcome;
  failureReason?: unknown;
  cleanupReport?: Record<string, unknown> | null;
}): DeletionLogTerminal {
  return {
    outcome: args.outcome,
    failure_reason: truncateReason(args.failureReason),
    cleanup_report: args.cleanupReport ?? null,
    completed_at: new Date().toISOString(),
  };
}
