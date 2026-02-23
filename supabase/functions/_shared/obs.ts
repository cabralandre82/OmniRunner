/**
 * Minimal observability helpers for Edge Functions.
 *
 * NEVER logs JWT, headers, or request body.
 * Only logs: request_id, fn, user_id, status, duration_ms, error_code.
 */

export function startTimer(): () => number {
  const t0 = Date.now();
  return () => Date.now() - t0;
}

export function logRequest(entry: {
  request_id: string;
  fn: string;
  user_id: string | null;
  status: number;
  duration_ms: number;
}): void {
  console.log(JSON.stringify(entry));
}

export function logError(entry: {
  request_id: string;
  fn: string;
  user_id: string | null;
  error_code: string;
  duration_ms: number;
}): void {
  console.error(JSON.stringify(entry));
}
