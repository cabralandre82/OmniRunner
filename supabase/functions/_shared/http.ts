/**
 * Standardized JSON response helpers for Supabase Edge Functions.
 *
 * Every response includes { ok, request_id } for traceability.
 * CORS headers are included automatically in all responses.
 */

import { CORS_HEADERS, corsHeaders } from "./cors.ts";

const BASE_HEADERS: Record<string, string> = {
  "Content-Type": "application/json",
};

export function jsonOk(
  data: Record<string, unknown>,
  requestId?: string,
  req?: Request,
): Response {
  const cors = req ? corsHeaders(req) : CORS_HEADERS;
  return new Response(
    JSON.stringify({ ok: true, request_id: requestId ?? null, ...data }),
    { status: 200, headers: { ...BASE_HEADERS, ...cors } },
  );
}

export function jsonErr(
  status: number,
  code: string,
  message: string,
  requestId?: string,
  details?: unknown,
  extraHeaders?: Record<string, string>,
  req?: Request,
): Response {
  // Sanitize: 403/404 use generic messages to avoid leaking resource existence
  const safeMessage =
    status === 403
      ? "Forbidden"
      : status === 404
        ? "Not found"
        : message;

  const body: Record<string, unknown> = {
    ok: false,
    request_id: requestId ?? null,
    error: { code, message: safeMessage },
  };
  if (details !== undefined && status !== 403 && status !== 404) {
    body.details = details;
  }
  const cors = req ? corsHeaders(req) : CORS_HEADERS;
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...BASE_HEADERS, ...cors, ...extraHeaders },
  });
}
