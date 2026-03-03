import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * list-purchases — Supabase Edge Function
 *
 * Lists billing purchases for a coaching group.
 * Only admin_master of the group can call this.
 * Returns purchases + summary (total credits acquired, by status).
 *
 * POST /list-purchases
 * Body: {
 *   group_id,
 *   status?:  "pending" | "paid" | "fulfilled" | "cancelled",
 *   limit?:   number (default 50, max 200),
 *   offset?:  number (default 0)
 * }
 *
 * See DECISAO 048 (admin_master only), DECISAO 049 (billing flow).
 */

const FN = "list-purchases";
const VALID_STATUSES = ["pending", "paid", "fulfilled", "cancelled"];
const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '1.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let userId: string | null = null;
  let httpStatus = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      httpStatus = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Auth ──────────────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let db: any;
    let user: { id: string; [key: string]: unknown };
    try {
      const auth = await requireUser(req);
      user = auth.user;
      db = auth.db;
      userId = user.id;
    } catch (e) {
      errorCode = "AUTH_ERROR";
      if (e instanceof AuthError) {
        httpStatus = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      httpStatus = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ──────────────────────────────────────────────────
    const rl = await checkRateLimit(
      db, user.id,
      { fn: FN, maxRequests: 60, windowSeconds: 60 },
      requestId,
    );
    if (!rl.allowed) {
      httpStatus = rl.status!;
      if (httpStatus >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body ───────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["group_id"]);
    } catch (e) {
      httpStatus = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { group_id } = body;
    const filterStatus = body.status as string | undefined;
    const limit = Math.min(
      Math.max(Number(body.limit) || DEFAULT_LIMIT, 1),
      MAX_LIMIT,
    );
    const offset = Math.max(Number(body.offset) || 0, 0);

    if (filterStatus && !VALID_STATUSES.includes(filterStatus)) {
      httpStatus = 400;
      return jsonErr(
        400, "INVALID_STATUS",
        `status must be one of: ${VALID_STATUSES.join(", ")}`,
        requestId,
      );
    }

    // ── 3. Verify admin_master role ─────────────────────────────────────
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || membership.role !== "admin_master") {
      httpStatus = 403;
      return jsonErr(
        403, "FORBIDDEN",
        "Only admin_master can view purchases",
        requestId,
      );
    }

    // ── 4. Query purchases ──────────────────────────────────────────────
    let query = db
      .from("billing_purchases")
      .select(
        "id, product_id, credits_amount, price_cents, currency, status, " +
        "payment_method, payment_reference, invoice_url, " +
        "requested_by, created_at, updated_at",
        { count: "exact" },
      )
      .eq("group_id", group_id)
      .order("created_at", { ascending: false })
      .range(offset, offset + limit - 1);

    if (filterStatus) {
      query = query.eq("status", filterStatus);
    }

    const { data: purchases, error, count } = await query;

    if (error) {
      const classified = classifyError(error);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── 5. Compute summary ──────────────────────────────────────────────
    const { data: summaryRows, error: sumErr } = await db
      .from("billing_purchases")
      .select("status, credits_amount, price_cents")
      .eq("group_id", group_id);

    // deno-lint-ignore no-explicit-any
    const summary: Record<string, any> = {
      total_purchases: 0,
      total_credits_fulfilled: 0,
      total_price_cents_fulfilled: 0,
      by_status: {} as Record<string, { count: number; credits: number; price_cents: number }>,
    };

    if (!sumErr && summaryRows) {
      summary.total_purchases = summaryRows.length;
      for (const row of summaryRows) {
        const s = row.status as string;
        if (!summary.by_status[s]) {
          summary.by_status[s] = { count: 0, credits: 0, price_cents: 0 };
        }
        summary.by_status[s].count += 1;
        summary.by_status[s].credits += row.credits_amount;
        summary.by_status[s].price_cents += row.price_cents;

        if (s === "fulfilled") {
          summary.total_credits_fulfilled += row.credits_amount;
          summary.total_price_cents_fulfilled += row.price_cents;
        }
      }
    }

    return jsonOk({
      purchases: purchases ?? [],
      count: count ?? (purchases ?? []).length,
      limit,
      offset,
      summary,
    }, requestId);
  } catch (_err) {
    httpStatus = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({
        request_id: requestId, fn: FN,
        user_id: userId, error_code: errorCode,
        duration_ms: elapsed(),
      });
    } else {
      logRequest({
        request_id: requestId, fn: FN,
        user_id: userId, status: httpStatus,
        duration_ms: elapsed(),
      });
    }
  }
});
