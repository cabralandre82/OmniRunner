/**
 * Canonical API error envelope (L14-05).
 *
 * Why: route handlers historically returned two incompatible shapes —
 *   `{ error: "string" }`         (~44 routes, mostly the financial /
 *                                   classic surface)
 *   `{ ok: false, error: { code } }` (~26 routes, training-plan +
 *                                   newer mobile-facing endpoints)
 *
 * Mobile and partner B2B clients had to special-case both, and many
 * call-sites silently lost the `code` field on retry / error display.
 * This module is the single source of truth for the new contract:
 *
 *   {
 *     ok: false,
 *     error: {
 *       code: "MACHINE_READABLE_SLUG",   // SCREAMING_SNAKE
 *       message: "Human-readable explanation",
 *       request_id: "uuid-or-null",      // L13-06 propagation
 *       details?: unknown                // optional, opt-in per call
 *     }
 *   }
 *
 * Success envelope is intentionally NOT touched by this module — each
 * endpoint owns its success schema (we don't want to retro-fit
 * `{ ok: true, data: ... }` over hundreds of consumers in the same
 * change). New endpoints SHOULD use `apiOk(data)` though, so the
 * contract crystallises naturally.
 *
 * Cross-references:
 *   - L13-06: `request_id` is sourced from the request header that the
 *     middleware now reliably propagates.
 *   - L14-01: when OpenAPI generation lands, this envelope becomes the
 *     `ApiError` schema in `components/schemas`.
 */

import { NextResponse, type NextRequest } from "next/server";

/**
 * Canonical machine-readable error codes.
 *
 * The list is intentionally small and grows only when an existing code
 * cannot describe the failure. Every code MUST round-trip through
 * tests so removing one is a breaking change visible in CI.
 *
 * Per-domain codes (e.g. swap-specific `not_open`, custody-specific
 * `INSUFFICIENT_BACKING`) are still allowed — they live next to the
 * domain helpers and appear in `error.code` exactly as defined; this
 * registry only enumerates the *cross-cutting* ones.
 */
export const COMMON_ERROR_CODES = [
  "UNAUTHORIZED",
  "FORBIDDEN",
  "NOT_FOUND",
  "CONFLICT",
  "GONE",
  "VALIDATION_FAILED",
  "RATE_LIMITED",
  "INTERNAL_ERROR",
  "SERVICE_UNAVAILABLE",
  "FEATURE_DISABLED",
  "NO_GROUP_SESSION",
] as const;

export type CommonErrorCode = (typeof COMMON_ERROR_CODES)[number];

/**
 * The body shape every error response wraps. `details` is opt-in; do
 * NOT include large payloads or PII.
 */
export interface ApiErrorBody {
  ok: false;
  error: {
    code: string;
    message: string;
    request_id: string | null;
    details?: unknown;
  };
}

export interface ApiOkBody<T> {
  ok: true;
  data: T;
}

export interface ApiErrorOptions {
  /** Override / set the `request_id` that goes into the body. */
  requestId?: string | null;
  /** Optional structured details (small JSON object, no PII). */
  details?: unknown;
  /** Extra response headers (e.g. `Retry-After`). */
  headers?: Record<string, string>;
}

/**
 * Resolve the request id from the request headers (or accept a
 * pre-computed value). Returns `null` when neither is available so
 * the field is always present in the JSON.
 */
export function resolveRequestId(
  source?: NextRequest | string | null,
): string | null {
  if (source == null) return null;
  if (typeof source === "string") return source || null;
  return source.headers.get("x-request-id");
}

/**
 * Build a JSON error response with the canonical envelope. The
 * `request_id` is set to the value carried by the L13-06 middleware
 * pipeline (or any explicit override).
 *
 * Example:
 *   return apiError(req, "UNAUTHORIZED", "Missing session", 401);
 *   return apiError(req, "RATE_LIMITED", "Too many requests", 429, {
 *     headers: { "Retry-After": "60" },
 *   });
 */
export function apiError(
  reqOrId: NextRequest | string | null | undefined,
  code: string,
  message: string,
  status: number,
  options?: ApiErrorOptions,
): NextResponse<ApiErrorBody> {
  const requestId =
    options?.requestId !== undefined
      ? options.requestId
      : resolveRequestId(reqOrId);
  const body: ApiErrorBody = {
    ok: false,
    error: {
      code,
      message,
      request_id: requestId,
      ...(options?.details !== undefined ? { details: options.details } : {}),
    },
  };
  const init: ResponseInit = { status };
  if (options?.headers) init.headers = options.headers;
  return NextResponse.json(body, init);
}

/**
 * Build a JSON success response. Endpoints already returning their own
 * shape (e.g. `{ offers }`) should keep doing so — `apiOk` is for new
 * endpoints adopting the canonical envelope.
 */
export function apiOk<T>(
  data: T,
  init?: ResponseInit,
): NextResponse<ApiOkBody<T>> {
  return NextResponse.json({ ok: true, data }, init);
}

/**
 * Convenience helpers for the most common shapes. Each one is just a
 * thin wrapper but keeping them named makes call-sites readable
 * (`apiUnauthorized(req)` instead of `apiError(req, "UNAUTHORIZED", "Unauthorized", 401)`).
 */
export function apiUnauthorized(
  req: NextRequest | null | undefined,
  message = "Authentication required",
) {
  return apiError(req, "UNAUTHORIZED", message, 401);
}

export function apiForbidden(
  req: NextRequest | null | undefined,
  message = "Forbidden",
) {
  return apiError(req, "FORBIDDEN", message, 403);
}

export function apiNotFound(
  req: NextRequest | null | undefined,
  message = "Resource not found",
) {
  return apiError(req, "NOT_FOUND", message, 404);
}

export function apiValidationFailed(
  req: NextRequest | null | undefined,
  message: string,
  details?: unknown,
) {
  return apiError(req, "VALIDATION_FAILED", message, 400, { details });
}

export function apiRateLimited(
  req: NextRequest | null | undefined,
  retryAfterSec?: number,
  message = "Too many requests",
) {
  const headers: Record<string, string> = {};
  if (retryAfterSec !== undefined && retryAfterSec >= 0) {
    headers["Retry-After"] = String(Math.ceil(retryAfterSec));
  }
  return apiError(req, "RATE_LIMITED", message, 429, { headers });
}

export function apiInternalError(
  req: NextRequest | null | undefined,
  message = "Internal server error",
) {
  return apiError(req, "INTERNAL_ERROR", message, 500);
}

export function apiServiceUnavailable(
  req: NextRequest | null | undefined,
  message = "Service temporarily unavailable",
  retryAfterSec?: number,
) {
  const headers: Record<string, string> = {};
  if (retryAfterSec !== undefined && retryAfterSec >= 0) {
    headers["Retry-After"] = String(Math.ceil(retryAfterSec));
  }
  return apiError(req, "SERVICE_UNAVAILABLE", message, 503, { headers });
}

export function apiNoGroupSession(req: NextRequest | null | undefined) {
  return apiError(
    req,
    "NO_GROUP_SESSION",
    "No active portal group session",
    403,
  );
}
