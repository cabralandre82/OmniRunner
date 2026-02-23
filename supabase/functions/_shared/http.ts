/**
 * Standardized JSON response helpers for Supabase Edge Functions.
 *
 * Every response includes { ok, request_id } for traceability.
 * CORS headers are included automatically in all responses.
 */

import { CORS_HEADERS } from "./cors.ts";

const HEADERS: Record<string, string> = {
  "Content-Type": "application/json",
  ...CORS_HEADERS,
};

export function jsonOk(
  data: Record<string, unknown>,
  requestId?: string,
): Response {
  return new Response(
    JSON.stringify({ ok: true, request_id: requestId ?? null, ...data }),
    { status: 200, headers: HEADERS },
  );
}

export function jsonErr(
  status: number,
  code: string,
  message: string,
  requestId?: string,
  details?: unknown,
  extraHeaders?: Record<string, string>,
): Response {
  const body: Record<string, unknown> = {
    ok: false,
    request_id: requestId ?? null,
    error: { code, message },
  };
  if (details !== undefined) {
    body.details = details;
  }
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...HEADERS, ...extraHeaders },
  });
}
