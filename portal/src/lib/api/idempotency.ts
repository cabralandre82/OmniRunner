/**
 * Server-side idempotency middleware (L18-02).
 *
 * Purpose: provide ONE pattern for "this request must run at most
 * once even if the client retries". Replaces ad-hoc per-RPC
 * idempotency that the audit (Lente 18, item 18.2) flagged as
 * inconsistent — `confirm_custody_deposit` used FOR UPDATE +
 * status check, `execute_burn_atomic` used wallet FOR UPDATE,
 * `execute_swap` used UUID ordering, and `execute_withdrawal` +
 * `distribute-coins` had no idempotency at all.
 *
 * Backed by `public.idempotency_keys` + `fn_idem_begin` /
 * `fn_idem_finalize` / `fn_idem_release` (migration
 * `20260419120000_l18_idempotency_keys_unified.sql`).
 *
 * Usage in a route handler:
 *
 *   export async function POST(req: NextRequest) {
 *     // ... auth, rate limit, validation ...
 *     const { actor: { id: userId } } = auth;
 *     const body = parsed.data;
 *
 *     return withIdempotency({
 *       request: req,
 *       namespace: "custody.withdraw",
 *       actorId: userId,
 *       requestBody: body,
 *       handler: async () => {
 *         // do the actual mutation; return { status, body }
 *         const withdrawal = await createWithdrawal(...);
 *         return { status: 200, body: { withdrawal } };
 *       },
 *     });
 *   }
 *
 * Behaviour matrix:
 *
 *   | client header | DB state           | wrapper does               |
 *   |---------------|--------------------|----------------------------|
 *   | missing       | —                  | call handler, no caching   |
 *   |               |                    | (back-compat with legacy)  |
 *   | invalid       | —                  | 400 IDEMPOTENCY_KEY_INVALID|
 *   | new           | none               | claim, run handler, store  |
 *   | repeat        | completed          | replay cached response     |
 *   | repeat        | claimed (fresh)    | run handler again (DB-side |
 *   |               |                    | resource locks dedupe)     |
 *   | repeat        | claimed (stale)    | reclaim, run handler       |
 *   | repeat (diff  | any                | 409 IDEMPOTENCY_KEY_CONFLICT
 *   | body)         |                    |                            |
 *
 * Why not enforce missing-header → 400?
 *
 *   We do NOT make the header mandatory at the middleware level —
 *   per-route helpers may decide to require it (e.g.
 *   `requireIdempotencyKey()` is exported below for that use). For
 *   migrations to ship safely the wrapper degrades gracefully when
 *   no key is sent; `custody.withdraw` and `coins.distribute` will
 *   layer the requirement on top.
 *
 * Hash:
 *
 *   The request body is canonicalised (recursive sort of object
 *   keys) before hashing so that semantically identical bodies
 *   produce the same hash regardless of property order.
 *
 * Contract with NextResponse:
 *
 *   The handler returns `{ status, body }` (plain JSON-serializable
 *   body). The wrapper builds the NextResponse, includes the
 *   request_id propagation, and stores `body` in the cache for
 *   replay. We deliberately do NOT cache binary / streamed
 *   responses — those should never use this wrapper.
 */

import { createHash } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { createServiceClient } from "@/lib/supabase/service";
import { logger } from "@/lib/logger";
import { apiError, resolveRequestId } from "./errors";

/** Accepted formats: UUID v4 OR opaque [A-Za-z0-9_-]{8,128}. */
export const IDEMPOTENCY_KEY_RE =
  /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_-]{8,128})$/i;

export interface IdempotencyHandlerResult {
  status: number;
  body: unknown;
  /** Optional headers to merge into the final NextResponse. */
  headers?: Record<string, string>;
}

export interface WithIdempotencyOptions {
  request: NextRequest;
  /** Logical bucket (e.g. `"custody.withdraw"`). Lowercased a-z0-9_./ */
  namespace: string;
  /** Stable identity of the caller (typically `auth.user.id`). */
  actorId: string;
  /** Body to hash; usually the parsed Zod output. */
  requestBody: unknown;
  /** Override the default 24h TTL. */
  ttlSeconds?: number;
  /**
   * If true, missing/invalid `x-idempotency-key` header returns 400
   * BEFORE the handler runs. Default false (legacy-friendly).
   */
  required?: boolean;
  /**
   * Override the body cache key. By default we use the canonical
   * stringification of `requestBody`. Provide this if your handler
   * mutates the body (e.g. fills in defaults) and you want the
   * stored hash to reflect the post-mutation form.
   */
  hashOverride?: string;
  /** The actual mutation. Called at most once per (ns, actor, key). */
  handler: () => Promise<IdempotencyHandlerResult>;
}

/**
 * Stable JSON canonicalisation: sort object keys recursively. Arrays
 * preserve order. Skips undefined keys (matches JSON.stringify).
 */
export function canonicalize(value: unknown): string {
  return JSON.stringify(sortKeysDeep(value));
}

function sortKeysDeep(v: unknown): unknown {
  if (v === null || typeof v !== "object") return v;
  if (Array.isArray(v)) return v.map(sortKeysDeep);
  const obj = v as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(obj).sort()) {
    if (obj[k] !== undefined) out[k] = sortKeysDeep(obj[k]);
  }
  return out;
}

/**
 * SHA-256 hex digest of an arbitrary string. We use Node's
 * `node:crypto` directly (instead of WebCrypto's `crypto.subtle`)
 * because it is synchronous, available in vitest without
 * configuration, and produces exactly the same hex bytes Postgres
 * expects for `bytea` literals.
 */
function sha256Hex(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

/** Convert a hex string to a Postgres `bytea` literal (`\x<hex>`). */
function hexToBytea(hex: string): string {
  return `\\x${hex}`;
}

/**
 * Pull and validate the `x-idempotency-key` header.
 * Returns null if missing; throws an `Error` if present but invalid.
 */
export function readIdempotencyKey(request: NextRequest): string | null {
  const raw = request.headers.get("x-idempotency-key");
  if (raw == null) return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  if (!IDEMPOTENCY_KEY_RE.test(trimmed)) {
    throw new IdempotencyKeyInvalidError(trimmed);
  }
  return trimmed;
}

export class IdempotencyKeyInvalidError extends Error {
  constructor(public readonly received: string) {
    super("Invalid x-idempotency-key format");
  }
}

interface BeginRow {
  action: "execute" | "replay" | "mismatch";
  replay_status: number | null;
  replay_body: unknown;
  stale_recovered: boolean;
}

/**
 * Wraps a handler with the idempotency lifecycle.
 *
 * Returns the NextResponse produced by either the cached replay or
 * the freshly-executed handler.
 */
export async function withIdempotency(
  opts: WithIdempotencyOptions,
): Promise<NextResponse> {
  const { request, namespace, actorId, requestBody, handler } = opts;

  let key: string | null;
  try {
    key = readIdempotencyKey(request);
  } catch (e) {
    if (e instanceof IdempotencyKeyInvalidError) {
      return apiError(
        request,
        "IDEMPOTENCY_KEY_INVALID",
        "Invalid x-idempotency-key format",
        400,
        {
          details: {
            hint: "Send a UUID v4 or opaque [A-Za-z0-9_-]{8,128} in x-idempotency-key.",
          },
        },
      );
    }
    throw e;
  }

  if (key == null) {
    if (opts.required) {
      return apiError(
        request,
        "IDEMPOTENCY_KEY_REQUIRED",
        "Missing x-idempotency-key header",
        400,
        {
          details: {
            hint: "Send a UUID v4 in x-idempotency-key to make this request safely retryable.",
          },
        },
      );
    }
    const result = await handler();
    return buildResponse(result, request);
  }

  const hashSource =
    opts.hashOverride !== undefined ? opts.hashOverride : canonicalize(requestBody);
  const hashHex = sha256Hex(hashSource);

  const db = createServiceClient();

  const begin = await db.rpc("fn_idem_begin" as any, {
    p_namespace: namespace,
    p_actor_id: actorId,
    p_key: key,
    p_request_hash: hexToBytea(hashHex),
    p_ttl_seconds: opts.ttlSeconds ?? 86400,
  });

  if (begin.error) {
    logger.error("[idempotency] fn_idem_begin failed", begin.error, {
      namespace,
      actor_id_present: Boolean(actorId),
    });
    return apiError(
      request,
      "IDEMPOTENCY_BACKEND_ERROR",
      "Idempotency layer unavailable",
      503,
    );
  }

  const beginRow = extractBeginRow(begin.data);
  if (!beginRow) {
    logger.error("[idempotency] empty fn_idem_begin response", new Error("empty"), {
      namespace,
    });
    return apiError(
      request,
      "IDEMPOTENCY_BACKEND_ERROR",
      "Idempotency layer returned no row",
      503,
    );
  }

  if (beginRow.action === "mismatch") {
    return apiError(
      request,
      "IDEMPOTENCY_KEY_CONFLICT",
      "x-idempotency-key was reused with a different request body",
      409,
      {
        details: {
          hint: "Use a fresh idempotency key for a new request, or repeat the original body to replay.",
        },
      },
    );
  }

  if (beginRow.action === "replay") {
    const status = beginRow.replay_status ?? 200;
    const body = beginRow.replay_body ?? null;
    const requestId = resolveRequestId(request);
    const response = NextResponse.json(body, { status });
    response.headers.set("x-idempotent-replay", "true");
    if (requestId) response.headers.set("x-request-id", requestId);
    return response;
  }

  let result: IdempotencyHandlerResult;
  try {
    result = await handler();
  } catch (e) {
    const release = await db.rpc("fn_idem_release" as any, {
      p_namespace: namespace,
      p_actor_id: actorId,
      p_key: key,
    });
    if (release.error) {
      logger.warn("[idempotency] fn_idem_release failed", {
        namespace,
        error: release.error.message,
      });
    }
    throw e;
  }

  const finalize = await db.rpc("fn_idem_finalize" as any, {
    p_namespace: namespace,
    p_actor_id: actorId,
    p_key: key,
    p_status_code: result.status,
    p_response: result.body ?? null,
  });

  if (finalize.error) {
    logger.warn("[idempotency] fn_idem_finalize failed", {
      namespace,
      error: finalize.error.message,
    });
  }

  return buildResponse(result, request);
}

function buildResponse(
  result: IdempotencyHandlerResult,
  request: NextRequest,
): NextResponse {
  const requestId = resolveRequestId(request);
  const init: ResponseInit = { status: result.status };
  if (result.headers) init.headers = result.headers;
  const response = NextResponse.json(result.body ?? null, init);
  if (requestId && !response.headers.get("x-request-id")) {
    response.headers.set("x-request-id", requestId);
  }
  return response;
}

function extractBeginRow(data: unknown): BeginRow | null {
  if (data == null) return null;
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  if (typeof r.action !== "string") return null;
  return {
    action: r.action as BeginRow["action"],
    replay_status:
      typeof r.replay_status === "number" ? r.replay_status : null,
    replay_body: r.replay_body ?? null,
    stale_recovered: Boolean(r.stale_recovered),
  };
}
