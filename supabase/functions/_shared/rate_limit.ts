/**
 * Per-user rate limiting via Postgres RPC (increment_rate_limit).
 *
 * On RPC failure → 503 RATE_LIMIT_UNAVAILABLE (makes the problem visible).
 * On success + over limit → 429 RATE_LIMIT with Retry-After.
 */

import { jsonErr } from "./http.ts";

export interface RateLimitOpts {
  fn: string;
  maxRequests: number;
  windowSeconds: number;
}

export interface RateLimitResult {
  allowed: boolean;
  status?: number;
  response?: Response;
}

export async function checkRateLimit(
  // deno-lint-ignore no-explicit-any
  db: any,
  userId: string,
  opts: RateLimitOpts,
  requestId: string,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await db.rpc("increment_rate_limit", {
      p_user_id: userId,
      p_fn: opts.fn,
      p_window_seconds: opts.windowSeconds,
    });

    if (error) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: opts.fn,
        user_id: userId,
        error_code: "RATE_LIMIT_RPC_ERROR",
        detail: error.message,
      }));
      return {
        allowed: false,
        status: 503,
        response: jsonErr(
          503,
          "RATE_LIMIT_UNAVAILABLE",
          "Rate limit service temporarily unavailable",
          requestId,
        ),
      };
    }

    const count = typeof data === "number" ? data : NaN;
    if (Number.isNaN(count)) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: opts.fn,
        user_id: userId,
        error_code: "RATE_LIMIT_RPC_ERROR",
        detail: `Unexpected RPC return: ${typeof data}`,
      }));
      return {
        allowed: false,
        status: 503,
        response: jsonErr(
          503,
          "RATE_LIMIT_UNAVAILABLE",
          "Rate limit service temporarily unavailable",
          requestId,
        ),
      };
    }

    if (count > opts.maxRequests) {
      return {
        allowed: false,
        status: 429,
        response: jsonErr(
          429,
          "RATE_LIMIT",
          `Too many requests. Limit: ${opts.maxRequests}/${opts.windowSeconds}s`,
          requestId,
          undefined,
          { "Retry-After": String(opts.windowSeconds) },
        ),
      };
    }

    return { allowed: true };
  } catch (err) {
    console.error(JSON.stringify({
      request_id: requestId,
      fn: opts.fn,
      user_id: userId,
      error_code: "RATE_LIMIT_RPC_ERROR",
      detail: (err as Error).message,
    }));
    return {
      allowed: false,
      status: 503,
      response: jsonErr(
        503,
        "RATE_LIMIT_UNAVAILABLE",
        "Rate limit service temporarily unavailable",
        requestId,
      ),
    };
  }
}
