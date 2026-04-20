import type { NextRequest } from "next/server";
import { z } from "zod";
import { settleClearingChunk } from "@/lib/clearing";
import {
  apiError,
  apiOk,
  apiUnauthorized,
  apiValidationFailed,
  apiServiceUnavailable,
} from "@/lib/api/errors";
import { logger } from "@/lib/logger";
import { metrics } from "@/lib/metrics";
import { withErrorHandler } from "@/lib/api-handler";
import { timingSafeEqual } from "node:crypto";

/**
 * L02-10 — POST /api/cron/settle-clearing-batch
 *
 * Operator-callable replay surface for the clearing settlement
 * backlog. The canonical path is the in-DB pg_cron job
 * `settle-clearing-batch` (`* * * * *` calling
 * `fn_settle_clearing_batch_safe`); this route exists as:
 *
 *   1. Manual escape from `CRON_HEALTH_RUNBOOK` when ops needs to
 *      drain backlog faster than the cron cadence (e.g. after a
 *      custody freeze is lifted).
 *   2. External cron platforms (Vercel Cron, GitHub Actions,
 *      Cloudflare Cron) that can't reach pg_cron directly.
 *
 * The route loops `settleClearingChunk(limit=50)` calls until either:
 *   • `remaining = 0` (backlog drained for the window)
 *   • `max_chunks` reached (caller-bounded — defaults to 5)
 *   • elapsed time exceeds the soft budget (defaults to 45 s,
 *     comfortably under the Vercel Pro 60 s response cap)
 *
 * Auth: `Authorization: Bearer ${CRON_SECRET}` constant-time compare.
 * If `CRON_SECRET` is unset (e.g. local dev), the route returns 503
 * rather than silently allowing unauthenticated traffic.
 *
 * Response:
 *   {
 *     ok: true,
 *     data: {
 *       chunks_processed:   number,
 *       total_processed:    number,
 *       total_settled:      number,
 *       total_insufficient: number,
 *       total_failed:       number,
 *       remaining:          number,   // post-loop snapshot
 *       drained:            boolean,  // remaining === 0
 *       window_hours:       number,
 *       limit:              number,
 *       latency_ms:         number,
 *       stop_reason:        "drained" | "max_chunks" | "time_budget" | "no_progress"
 *     }
 *   }
 *
 * On RPC error mid-loop, the route returns the partial counts so far
 * with the stop reason. The cron job at the SQL layer is the source
 * of truth for retry; this surface MUST be safe to retry blindly.
 */

export const runtime = "nodejs";
export const maxDuration = 60;

const bodySchema = z
  .object({
    window_hours: z
      .number()
      .int()
      .positive()
      .max(8760)
      .optional(),
    limit: z.number().int().positive().max(500).optional(),
    max_chunks: z.number().int().positive().max(20).optional(),
    debtor_group_id: z.string().uuid().optional(),
  })
  .strict();

const DEFAULT_WINDOW_HOURS = 168;
const DEFAULT_LIMIT = 50;
const DEFAULT_MAX_CHUNKS = 5;
const SOFT_TIME_BUDGET_MS = 45_000;
const MAX_BODY_BYTES = 4 * 1024;

function constantTimeBearerEqual(
  provided: string,
  expected: string,
): boolean {
  const a = Buffer.from(provided, "utf8");
  const b = Buffer.from(expected, "utf8");
  if (a.length !== b.length) {
    timingSafeEqual(a, a);
    return false;
  }
  return timingSafeEqual(a, b);
}

function authorizeCron(req: NextRequest):
  | { ok: true }
  | { ok: false; status: number; reason: string } {
  const secret = process.env.CRON_SECRET;
  if (!secret || secret.length < 16) {
    return {
      ok: false,
      status: 503,
      reason: "CRON_SECRET unset or too short (min 16 chars)",
    };
  }
  const header = req.headers.get("authorization") ?? "";
  if (!header.startsWith("Bearer ")) {
    return { ok: false, status: 401, reason: "missing bearer" };
  }
  const token = header.slice("Bearer ".length).trim();
  if (!token) {
    return { ok: false, status: 401, reason: "empty bearer" };
  }
  if (!constantTimeBearerEqual(token, secret)) {
    return { ok: false, status: 401, reason: "bearer mismatch" };
  }
  return { ok: true };
}

// L17-01 — outermost safety-net: throws inesperados (signal de auth
// timing safe, body parse, métrica out-of-band) viram 500 INTERNAL_ERROR
// canônico em vez de stack cru. Cron interno do pg_cron continua sendo
// a fonte autoritativa; este endpoint é replay manual / external cron
// (ver runbook CRON_HEALTH_RUNBOOK.md).
export const POST = withErrorHandler(_post, "api.cron.settle-clearing-batch.post");

async function _post(req: NextRequest) {
  const startedAt = Date.now();

  const auth = authorizeCron(req);
  if (!auth.ok) {
    metrics.increment("cron.settle_clearing.blocked", { reason: auth.reason });
    if (auth.status === 503) {
      return apiServiceUnavailable(req, "Cron secret not configured");
    }
    return apiUnauthorized(req, "Invalid cron credentials");
  }

  const contentLengthHeader = req.headers.get("content-length");
  if (
    contentLengthHeader &&
    Number.isFinite(Number(contentLengthHeader)) &&
    Number(contentLengthHeader) > MAX_BODY_BYTES
  ) {
    metrics.increment("cron.settle_clearing.blocked", {
      reason: "body_too_large",
    });
    return apiError(req, "PAYLOAD_TOO_LARGE", "Body exceeds 4 KiB cap", 413);
  }

  let parsedBody: z.infer<typeof bodySchema> = {};
  const rawText = await req.text().catch(() => "");
  if (Buffer.byteLength(rawText, "utf8") > MAX_BODY_BYTES) {
    metrics.increment("cron.settle_clearing.blocked", {
      reason: "body_too_large",
    });
    return apiError(req, "PAYLOAD_TOO_LARGE", "Body exceeds 4 KiB cap", 413);
  }
  if (rawText.trim()) {
    let json: unknown;
    try {
      json = JSON.parse(rawText);
    } catch {
      metrics.increment("cron.settle_clearing.blocked", {
        reason: "invalid_json",
      });
      return apiValidationFailed(req, "Invalid JSON body");
    }
    const parsed = bodySchema.safeParse(json);
    if (!parsed.success) {
      metrics.increment("cron.settle_clearing.blocked", { reason: "schema" });
      return apiValidationFailed(
        req,
        parsed.error.issues[0]?.message ?? "Invalid body",
        parsed.error.flatten(),
      );
    }
    parsedBody = parsed.data;
  }

  const windowHours = parsedBody.window_hours ?? DEFAULT_WINDOW_HOURS;
  const limit = parsedBody.limit ?? DEFAULT_LIMIT;
  const maxChunks = parsedBody.max_chunks ?? DEFAULT_MAX_CHUNKS;
  const debtorGroupId = parsedBody.debtor_group_id;

  const windowEnd = new Date();
  const windowStart = new Date(
    windowEnd.getTime() - windowHours * 60 * 60 * 1000,
  );

  let chunksProcessed = 0;
  let totalProcessed = 0;
  let totalSettled = 0;
  let totalInsufficient = 0;
  let totalFailed = 0;
  let remaining = 0;
  let stopReason:
    | "drained"
    | "max_chunks"
    | "time_budget"
    | "no_progress" = "drained";

  for (let i = 0; i < maxChunks; i++) {
    if (Date.now() - startedAt >= SOFT_TIME_BUDGET_MS) {
      stopReason = "time_budget";
      break;
    }

    let result: Awaited<ReturnType<typeof settleClearingChunk>>;
    try {
      result = await settleClearingChunk({
        windowStart,
        windowEnd,
        limit,
        debtorGroupId,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error("settleClearingChunk failed", err, {
        chunk_index: i,
        window_hours: windowHours,
        limit,
      });
      metrics.increment("cron.settle_clearing.error", {
        reason: "chunk_rpc",
      });
      return apiError(
        req,
        "CHUNK_RPC_ERROR",
        `Chunk ${i + 1}/${maxChunks} failed: ${message}`,
        500,
        {
          details: {
            chunks_processed: chunksProcessed,
            total_settled: totalSettled,
            total_failed: totalFailed,
          },
        },
      );
    }

    chunksProcessed++;
    totalProcessed += result.processed;
    totalSettled += result.settled;
    totalInsufficient += result.insufficient;
    totalFailed += result.failed;
    remaining = result.remaining;

    if (result.processed === 0) {
      stopReason = "no_progress";
      break;
    }
    if (result.remaining === 0) {
      stopReason = "drained";
      break;
    }
    if (chunksProcessed >= maxChunks) {
      stopReason = "max_chunks";
      break;
    }
  }

  const latencyMs = Date.now() - startedAt;

  metrics.timing("cron.settle_clearing.duration_ms", latencyMs);
  metrics.increment("cron.settle_clearing.completed", { reason: stopReason });
  metrics.gauge("cron.settle_clearing.settled_per_run", totalSettled);
  metrics.gauge("cron.settle_clearing.remaining", remaining);

  logger.info("settle-clearing-batch chunked drain completed", {
    chunks_processed: chunksProcessed,
    total_processed: totalProcessed,
    total_settled: totalSettled,
    total_insufficient: totalInsufficient,
    total_failed: totalFailed,
    remaining,
    drained: remaining === 0,
    stop_reason: stopReason,
    latency_ms: latencyMs,
    window_hours: windowHours,
    limit,
  });

  return apiOk({
    chunks_processed: chunksProcessed,
    total_processed: totalProcessed,
    total_settled: totalSettled,
    total_insufficient: totalInsufficient,
    total_failed: totalFailed,
    remaining,
    drained: remaining === 0,
    window_hours: windowHours,
    limit,
    latency_ms: latencyMs,
    stop_reason: stopReason,
  });
}
