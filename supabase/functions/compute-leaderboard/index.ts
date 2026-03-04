import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { log } from "../_shared/logger.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";

/**
 * compute-leaderboard v2 — Supabase Edge Function
 *
 * Materializes leaderboard snapshots for 3 scopes:
 *   global       — all users with verified sessions
 *   assessoria   — members of a coaching_group
 *   championship — participants with active badge
 *
 * POST /compute-leaderboard
 * Body:
 *   { scope: "global"|"assessoria"|"championship",
 *     period?: "weekly"|"monthly",
 *     coaching_group_id?: UUID,     (required when scope=assessoria)
 *     championship_id?: UUID        (required when scope=championship)
 *   }
 */

const MS_PER_DAY = 86_400_000;

type Scope = "global" | "assessoria" | "championship" | "batch_assessoria";
type Period = "weekly" | "monthly";
const BATCH_SIZE = 100;

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
  const FN = "compute-leaderboard";
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Authenticate ──────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let db: any;
    try {
      const auth = await requireUser(req);
      userId = auth.user.id;
      db = auth.db;
    } catch (e) {
      errorCode = "AUTH_ERROR";
      if (e instanceof AuthError) {
        status = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      status = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ───────────────────────────────────────────────────
    const rl = await checkRateLimit(db, userId!, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body ────────────────────────────────────────────────────
    let body: Record<string, unknown> = {};
    try {
      body = await requireJson(req);
    } catch { /* ping mode */ }

    // ── 3. Ping mode ─────────────────────────────────────────────────────
    if (!body.scope) {
      return jsonOk({
        status: "ok",
        note: "auth_ok_no_payload",
        auth_user_id: userId,
      }, requestId);
    }

    const scope = body.scope as Scope;
    if (!["global", "assessoria", "championship", "batch_assessoria"].includes(scope)) {
      status = 400;
      return jsonErr(400, "INVALID_SCOPE", "scope must be global, assessoria, championship, or batch_assessoria", requestId);
    }

    const period: Period = (body.period as Period) ?? "weekly";
    if (!["weekly", "monthly"].includes(period)) {
      status = 400;
      return jsonErr(400, "INVALID_PERIOD", "period must be weekly or monthly", requestId);
    }

    const now = new Date();
    const { key, startMs, endMs } = getPeriodBounds(now, period);

    let computed = 0;

    // ── 4. Dispatch by scope ─────────────────────────────────────────────

    if (scope === "global") {
      const { data: count, error } = await db.rpc("compute_leaderboard_global", {
        p_period: period,
        p_period_key: key,
        p_start_ms: startMs,
        p_end_ms: endMs,
      });
      if (error) {
        status = 500;
        errorCode = "RPC_ERROR";
        return jsonErr(500, "RPC_ERROR", "Failed to compute global leaderboard", requestId);
      }
      computed = count ?? 0;

    } else if (scope === "assessoria") {
      try {
        requireFields(body, ["coaching_group_id"]);
      } catch (e) {
        if (e instanceof ValidationError) {
          status = 400;
          return jsonErr(400, e.code, e.message, requestId);
        }
        throw e;
      }

      const groupId = body.coaching_group_id as string;

      // Verify caller is a member of this coaching group
      const { data: membership } = await db
        .from("coaching_members")
        .select("id")
        .eq("group_id", groupId)
        .eq("user_id", userId)
        .limit(1)
        .maybeSingle();

      if (!membership) {
        status = 403;
        return jsonErr(403, "NOT_MEMBER", "Você não é membro desta assessoria", requestId);
      }

      const { data: count, error } = await db.rpc("compute_leaderboard_assessoria", {
        p_coaching_group_id: groupId,
        p_period: period,
        p_period_key: key,
        p_start_ms: startMs,
        p_end_ms: endMs,
      });
      if (error) {
        status = 500;
        errorCode = "RPC_ERROR";
        return jsonErr(500, "RPC_ERROR", "Failed to compute assessoria leaderboard", requestId);
      }
      computed = count ?? 0;

    } else if (scope === "championship") {
      try {
        requireFields(body, ["championship_id"]);
      } catch (e) {
        if (e instanceof ValidationError) {
          status = 400;
          return jsonErr(400, e.code, e.message, requestId);
        }
        throw e;
      }

      const champId = body.championship_id as string;

      // Verify championship exists and caller is participant or host staff
      const { data: champ } = await db
        .from("championships")
        .select("id, host_group_id, status")
        .eq("id", champId)
        .maybeSingle();

      if (!champ) {
        status = 404;
        return jsonErr(404, "NOT_FOUND", "Campeonato não encontrado", requestId);
      }

      if (!["open", "active", "completed"].includes(champ.status)) {
        status = 400;
        return jsonErr(400, "INVALID_STATUS", "Campeonato não está ativo", requestId);
      }

      // Check: is user a participant OR staff of host group?
      const [{ data: participant }, { data: hostStaff }] = await Promise.all([
        db.from("championship_participants")
          .select("id")
          .eq("championship_id", champId)
          .eq("user_id", userId)
          .limit(1)
          .maybeSingle(),
        db.from("coaching_members")
          .select("id")
          .eq("group_id", champ.host_group_id)
          .eq("user_id", userId)
          .in("role", ["admin_master", "coach", "assistant"])
          .limit(1)
          .maybeSingle(),
      ]);

      if (!participant && !hostStaff) {
        status = 403;
        return jsonErr(403, "NOT_AUTHORIZED", "Você não participa deste campeonato", requestId);
      }

      const { data: count, error } = await db.rpc("compute_leaderboard_championship", {
        p_championship_id: champId,
        p_period_key: key,
        p_start_ms: startMs,
        p_end_ms: endMs,
      });
      if (error) {
        status = 500;
        errorCode = "RPC_ERROR";
        return jsonErr(500, "RPC_ERROR", "Failed to compute championship leaderboard", requestId);
      }
      computed = count ?? 0;

    } else if (scope === "batch_assessoria") {
      // ── Batch mode: process ALL coaching groups in chunks of BATCH_SIZE ──
      const { data: allGroups, error: groupsErr } = await db
        .from("coaching_groups")
        .select("id")
        .order("id");

      if (groupsErr) {
        status = 500;
        errorCode = "RPC_ERROR";
        return jsonErr(500, "RPC_ERROR", "Failed to fetch coaching groups", requestId);
      }

      const groups = allGroups ?? [];
      const totalGroups = groups.length;
      let totalComputed = 0;
      let batchIndex = 0;
      let groupsProcessed = 0;
      const batchErrors: { group_id: string; error: string }[] = [];
      const DEADLINE_MS = 50_000;
      const loopStart = Date.now();
      let hitDeadline = false;
      const cursor = (body.cursor as string) ?? null;
      const cursorIdx = cursor
        ? groups.findIndex((g: { id: string }) => g.id > cursor)
        : 0;
      const startIdx = cursorIdx >= 0 ? cursorIdx : 0;

      log("info", "batch_assessoria: starting", {
        request_id: requestId,
        total_groups: totalGroups,
        start_index: startIdx,
        batch_size: BATCH_SIZE,
        period,
        period_key: key,
      });

      for (let i = startIdx; i < totalGroups; i += BATCH_SIZE) {
        if (Date.now() - loopStart > DEADLINE_MS) {
          hitDeadline = true;
          break;
        }

        batchIndex++;
        const chunk = groups.slice(i, i + BATCH_SIZE);
        const batchStart = Date.now();

        for (const g of chunk) {
          if (Date.now() - loopStart > DEADLINE_MS) {
            hitDeadline = true;
            break;
          }

          try {
            const { data: count, error } = await db.rpc("compute_leaderboard_assessoria", {
              p_coaching_group_id: g.id,
              p_period: period,
              p_period_key: key,
              p_start_ms: startMs,
              p_end_ms: endMs,
            });
            if (error) {
              batchErrors.push({ group_id: g.id, error: error.message ?? "rpc_error" });
            } else {
              totalComputed += count ?? 0;
            }
          } catch (err) {
            batchErrors.push({
              group_id: g.id,
              error: err instanceof Error ? err.message : "unknown",
            });
          }
          groupsProcessed++;
        }

        log("info", "batch_assessoria: batch completed", {
          request_id: requestId,
          batch: batchIndex,
          groups_in_batch: chunk.length,
          batch_duration_ms: Date.now() - batchStart,
        });

        if (hitDeadline) break;
      }

      const remaining = totalGroups - startIdx - groupsProcessed;
      const lastProcessedId = groupsProcessed > 0
        ? groups[startIdx + groupsProcessed - 1]?.id ?? null
        : cursor;

      if (hitDeadline) {
        log("warn", "batch_assessoria: deadline reached, returning partial", {
          request_id: requestId,
          groups_processed: groupsProcessed,
          groups_remaining: remaining,
          next_cursor: lastProcessedId,
        });
      }

      if (batchErrors.length > 0) {
        log("warn", "batch_assessoria: some groups failed", {
          request_id: requestId,
          failed_count: batchErrors.length,
          errors: batchErrors.slice(0, 10),
        });
      }

      log("info", "batch_assessoria: finished", {
        request_id: requestId,
        total_groups: totalGroups,
        groups_processed: groupsProcessed,
        total_computed: totalComputed,
        failed_count: batchErrors.length,
        total_duration_ms: elapsed(),
      });

      return jsonOk({
        status: hitDeadline ? "partial" : "ok",
        scope,
        period,
        period_key: key,
        total_groups: totalGroups,
        groups_processed: groupsProcessed,
        groups_remaining: remaining,
        entries_computed: totalComputed,
        failed_groups: batchErrors.length,
        errors: batchErrors.length > 0 ? batchErrors.slice(0, 10) : undefined,
        next_cursor: hitDeadline ? lastProcessedId : undefined,
      }, requestId);
    }

    log("info", "compute-leaderboard completed", {
      request_id: requestId,
      scope,
      period,
      entries_computed: computed,
      duration_ms: elapsed(),
    });

    return jsonOk({
      status: "ok",
      scope,
      period,
      period_key: key,
      entries_computed: computed,
    }, requestId);

  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status, duration_ms: elapsed() });
    }
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════════════════════

function getPeriodBounds(now: Date, period: Period): { key: string; startMs: number; endMs: number } {
  if (period === "weekly") {
    const day = now.getUTCDay() || 7;
    const monday = new Date(now);
    monday.setUTCDate(now.getUTCDate() - day + 1);
    monday.setUTCHours(0, 0, 0, 0);

    const sunday = new Date(monday);
    sunday.setUTCDate(monday.getUTCDate() + 6);
    sunday.setUTCHours(23, 59, 59, 999);

    const yearStart = new Date(Date.UTC(monday.getUTCFullYear(), 0, 1));
    const weekNo = Math.ceil(((monday.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7);
    const key = `${monday.getUTCFullYear()}-W${String(weekNo).padStart(2, "0")}`;

    return { key, startMs: monday.getTime(), endMs: sunday.getTime() };
  }

  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0, 23, 59, 59, 999));
  const key = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;

  return { key, startMs: start.getTime(), endMs: end.getTime() };
}
