import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { log } from "../_shared/logger.ts";

/**
 * archive-old-sessions — Supabase Edge Function (L12-06)
 *
 * Scheduled by pg_cron weekly ('45 3 * * 0') via
 * `public.fn_invoke_archive_sessions_safe()`.
 *
 * Purpose
 * ───────
 *   Call `public.fn_archive_sessions_chunk(batch_size, cutoff_months)`
 *   in a loop — ONE CHUNK PER RPC ROUND-TRIP = one transaction each =
 *   real COMMIT between chunks. This unblocks autovacuum between
 *   chunks, keeps snapshot windows short, and lets a mid-run kill
 *   preserve whatever progress was made.
 *
 *   See `supabase/migrations/20260421250000_l12_06_archive_sessions
 *   _chunked_commits.sql` for the SQL primitives.
 *
 * Request body (all optional)
 *   {
 *     "batch_size":       number    // default 500 (1..10000)
 *     "cutoff_months":    number    // default 6   (1..120)
 *     "max_batches":      number    // default 40  (hard cap per tick)
 *     "max_duration_ms":  number    // default 480000 = 8 min
 *   }
 *
 * Response
 *   {
 *     "ok":                true,
 *     "rows_moved_total":  N,
 *     "batches":           M,
 *     "duration_ms":       T,
 *     "terminated_by":     "no_more_pending" | "max_batches"
 *                          | "max_duration" | "chunk_error",
 *     "cutoff_ms":         bigint (as number)
 *   }
 *
 * Auth
 *   Service-role only (called by pg_net from pg_cron, or by ops via
 *   service-role Bearer). Any other caller gets 401.
 */

const FN = "archive-old-sessions";

const DEFAULT_BATCH_SIZE = 500;
const DEFAULT_CUTOFF_MONTHS = 6;
const DEFAULT_MAX_BATCHES = 40;
const DEFAULT_MAX_DURATION_MS = 480_000; // 8 minutes

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === "GET" && new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", version: "1.0.0" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!serviceKey || !supabaseUrl) {
      status = 500;
      errorCode = "CONFIG_ERROR";
      return jsonErr(500, "CONFIG_ERROR", "Server misconfiguration", requestId);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const bearer = authHeader.startsWith("Bearer ")
      ? authHeader.slice(7).trim()
      : "";
    if (bearer !== serviceKey) {
      status = 401;
      errorCode = "UNAUTHORIZED";
      return jsonErr(401, "UNAUTHORIZED", "Service role required", requestId);
    }

    let body: Record<string, unknown> = {};
    try {
      const text = await req.text();
      if (text.trim().length > 0) body = JSON.parse(text);
    } catch {
      status = 400;
      errorCode = "BAD_JSON";
      return jsonErr(400, "BAD_JSON", "Invalid JSON body", requestId);
    }

    const batchSize = clampInt(
      numberOr(body.batch_size, DEFAULT_BATCH_SIZE),
      1,
      10_000,
      DEFAULT_BATCH_SIZE,
    );
    const cutoffMonths = clampInt(
      numberOr(body.cutoff_months, DEFAULT_CUTOFF_MONTHS),
      1,
      120,
      DEFAULT_CUTOFF_MONTHS,
    );
    const maxBatches = clampInt(
      numberOr(body.max_batches, DEFAULT_MAX_BATCHES),
      1,
      500,
      DEFAULT_MAX_BATCHES,
    );
    const maxDurationMs = clampInt(
      numberOr(body.max_duration_ms, DEFAULT_MAX_DURATION_MS),
      1_000,
      540_000,
      DEFAULT_MAX_DURATION_MS,
    );

    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const startedAt = Date.now();
    let rowsMovedTotal = 0;
    let batches = 0;
    let cutoffMs: number | null = null;
    let terminatedBy:
      | "no_more_pending"
      | "max_batches"
      | "max_duration"
      | "chunk_error" = "no_more_pending";
    let lastErrorMessage: string | null = null;

    while (batches < maxBatches) {
      if (Date.now() - startedAt > maxDurationMs) {
        terminatedBy = "max_duration";
        break;
      }

      const { data, error } = await db.rpc("fn_archive_sessions_chunk", {
        p_batch_size: batchSize,
        p_cutoff_months: cutoffMonths,
      });

      if (error) {
        terminatedBy = "chunk_error";
        lastErrorMessage = error.message ?? String(error);
        log.error("fn_archive_sessions_chunk RPC failed", {
          error: lastErrorMessage,
          batch_index: batches,
        });
        break;
      }

      const chunk = (data ?? {}) as {
        moved_count?: number;
        more_pending?: boolean;
        cutoff_ms?: number;
      };
      const movedCount = Number(chunk.moved_count ?? 0) || 0;
      const morePending = Boolean(chunk.more_pending);
      if (chunk.cutoff_ms != null) cutoffMs = Number(chunk.cutoff_ms);

      rowsMovedTotal += movedCount;
      batches += 1;

      if (movedCount === 0 || !morePending) {
        terminatedBy = "no_more_pending";
        break;
      }

      if (batches >= maxBatches) {
        terminatedBy = "max_batches";
        break;
      }
    }

    const durationMs = Date.now() - startedAt;

    if (terminatedBy === "chunk_error") {
      status = 502;
      errorCode = "CHUNK_ERROR";
      return jsonErr(
        502,
        "CHUNK_ERROR",
        lastErrorMessage ?? "chunk RPC failed",
        requestId,
      );
    }

    return jsonOk(
      {
        rows_moved_total: rowsMovedTotal,
        batches,
        duration_ms: durationMs,
        terminated_by: terminatedBy,
        cutoff_ms: cutoffMs,
      },
      requestId,
    );
  } catch (err) {
    status = 500;
    errorCode = "INTERNAL";
    logError(FN, err, { requestId });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    logRequest(FN, {
      requestId,
      status,
      errorCode,
      durationMs: elapsed(),
    });
  }
});

function numberOr(v: unknown, fallback: number): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim().length > 0) {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

function clampInt(
  v: number,
  min: number,
  max: number,
  fallback: number,
): number {
  const n = Number.isFinite(v) ? Math.trunc(v) : fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}
