/**
 * Cursor-based pagination contract (L14-06).
 *
 * The legacy list endpoints (`GET /api/athletes`, several training-plan
 * endpoints) returned every row with no `limit`/`offset`/`cursor`
 * parameter. A group with 5 000 athletes therefore paid the cost of
 * megabyte payloads on every dropdown render.
 *
 * This module is the canonical, opt-in pagination protocol:
 *
 *   Request:    ?cursor=<opaque>&limit=<1..MAX>
 *   Response:   { items: [...], next_cursor: string | null, has_more: boolean }
 *
 * Why opaque cursors (vs offset)?
 *
 *   - Stable across inserts/deletes (offset shifts every page when a
 *     row is added at the head).
 *   - Lets us encode tie-breakers (e.g. `created_at, id`) without
 *     leaking column names to the client.
 *   - Future-proof: switching the underlying ordering doesn't break
 *     callers as long as they round-trip the cursor unchanged.
 *
 * The cursor is base64url-encoded JSON. We deliberately do NOT sign
 * it: pagination is not a security boundary (the underlying query is
 * always re-checked by RLS), and signing complicates rotation.
 *
 * Limits:
 *   - DEFAULT_PAGE_LIMIT = 50  (good UX default for staff dashboards)
 *   - MAX_PAGE_LIMIT     = 100 (server-enforced ceiling)
 *
 * Endpoints SHOULD pin those constants via `parsePaginationParams()`
 * which clamps values inside the safe range and rejects malformed
 * cursors with a typed error.
 */

import type { ApiErrorBody } from "./errors";

export const DEFAULT_PAGE_LIMIT = 50;
export const MAX_PAGE_LIMIT = 100;
export const MIN_PAGE_LIMIT = 1;

/**
 * Result of parsing a request's `?cursor=&limit=` query string.
 * Always returns a clamped numeric `limit` and a possibly-`null`
 * cursor object decoded from base64url.
 */
export interface ParsedPaginationParams<C = unknown> {
  limit: number;
  cursor: C | null;
}

export class PaginationError extends Error {
  constructor(
    message: string,
    public readonly code: "INVALID_CURSOR" | "INVALID_LIMIT",
  ) {
    super(message);
    this.name = "PaginationError";
  }
}

/**
 * Encode a structured cursor object as a URL-safe base64 string.
 * Returns `null` if the input is `null`/`undefined` so callers can
 * pipe directly into the response shape.
 */
export function encodeCursor<C>(value: C | null | undefined): string | null {
  if (value == null) return null;
  const json = JSON.stringify(value);
  return base64UrlEncode(json);
}

/**
 * Decode a cursor string back into its structured form. Throws
 * PaginationError("INVALID_CURSOR") for any malformed input — callers
 * usually catch and re-throw via `apiValidationFailed`.
 */
export function decodeCursor<C = unknown>(raw: string): C {
  let decoded: string;
  try {
    decoded = base64UrlDecode(raw);
  } catch {
    throw new PaginationError("Cursor is not valid base64url", "INVALID_CURSOR");
  }
  try {
    return JSON.parse(decoded) as C;
  } catch {
    throw new PaginationError("Cursor payload is not valid JSON", "INVALID_CURSOR");
  }
}

/**
 * Parse a URLSearchParams (or any object with `.get(name)`) into a
 * clamped `limit` + decoded `cursor`. Throws `PaginationError` for
 * caller-visible problems; pass-through everything else.
 */
export function parsePaginationParams<C = unknown>(
  params: URLSearchParams | { get(name: string): string | null },
  opts?: { defaultLimit?: number; maxLimit?: number },
): ParsedPaginationParams<C> {
  const defaultLimit = opts?.defaultLimit ?? DEFAULT_PAGE_LIMIT;
  const maxLimit = opts?.maxLimit ?? MAX_PAGE_LIMIT;

  const rawLimit = params.get("limit");
  let limit = defaultLimit;
  if (rawLimit !== null && rawLimit !== "") {
    if (!/^\d+$/.test(rawLimit)) {
      throw new PaginationError(
        "limit must be a positive integer",
        "INVALID_LIMIT",
      );
    }
    const n = Number(rawLimit);
    if (n < MIN_PAGE_LIMIT) {
      throw new PaginationError(
        `limit must be >= ${MIN_PAGE_LIMIT}`,
        "INVALID_LIMIT",
      );
    }
    limit = Math.min(n, maxLimit);
  }

  const rawCursor = params.get("cursor");
  const cursor =
    rawCursor !== null && rawCursor !== "" ? decodeCursor<C>(rawCursor) : null;

  return { limit, cursor };
}

/**
 * Standard pagination response shape. Generic over the item type so
 * route handlers keep their domain types — only the wrapper is
 * shared.
 */
export interface PaginatedResponse<T> {
  items: T[];
  next_cursor: string | null;
  has_more: boolean;
}

/**
 * Build the response envelope from a query result. The convention is
 * to fetch `limit + 1` rows from the DB, then call this helper:
 *
 *   const rows = await db.from("athletes").select("...").limit(limit + 1);
 *   return paginate(rows, limit, (last) => ({ created_at: last.created_at, id: last.id }));
 *
 * `extractCursor` runs ONLY when there is a next page; it receives
 * the last visible row (i.e. `items[limit-1]`), not the over-fetched
 * sentinel.
 */
export function paginate<T, C>(
  rows: T[],
  limit: number,
  extractCursor: (lastVisible: T) => C,
): PaginatedResponse<T> {
  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  const next_cursor =
    hasMore && items.length > 0
      ? encodeCursor(extractCursor(items[items.length - 1]))
      : null;
  return { items, next_cursor, has_more: hasMore };
}

// ─────────────────────────────────────────────────────────────────────────────
// base64url helpers — kept inline so this module has zero deps. Not
// exported because callers should always go through encode/decodeCursor.
// ─────────────────────────────────────────────────────────────────────────────

function base64UrlEncode(input: string): string {
  return Buffer.from(input, "utf8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64UrlDecode(input: string): string {
  if (!/^[A-Za-z0-9_-]+$/.test(input)) {
    throw new Error("Not base64url");
  }
  const padded = input + "=".repeat((4 - (input.length % 4)) % 4);
  const std = padded.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(std, "base64").toString("utf8");
}

/**
 * Runtime-checkable type so OpenAPI generation (L14-01) can wire up
 * `PaginatedResponse` and `ApiErrorBody` from the same place.
 */
export type ApiPaginatedOrError<T> = PaginatedResponse<T> | ApiErrorBody;
