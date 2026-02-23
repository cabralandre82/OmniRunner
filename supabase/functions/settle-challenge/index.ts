import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * settle-challenge — Supabase Edge Function
 *
 * Called by a cron job or manually to settle completed/expired challenges.
 * Computes results, distributes coin rewards, and creates ledger entries.
 *
 * Must run with service_role key (bypasses RLS).
 *
 * POST /settle-challenge
 * Body: { challenge_id: string }  — or empty to settle ALL due challenges.
 */

interface Participant {
  challenge_id: string;
  user_id: string;
  display_name: string;
  status: string;
  progress_value: number;
  last_submitted_at_ms: number | null;
  contributing_session_ids: string[];
  group_id: string | null;
  team: string | null;
}

interface Challenge {
  id: string;
  status: string;
  type: string;
  metric: string;
  target: number | null;
  entry_fee_coins: number;
  ends_at_ms: number | null;
  team_a_group_id: string | null;
  team_b_group_id: string | null;
}

interface ProfileGroup {
  id: string;
  active_coaching_group_id: string | null;
}

// ── Handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  const FN = "settle-challenge";
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
  if (req.method !== "POST") {
    status = 405;
    return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
  }

  // ── 1. Authenticate ────────────────────────────────────────────────
  let user: { id: string; [key: string]: unknown };
  // deno-lint-ignore no-explicit-any
  let db: any;
  try {
    const auth = await requireUser(req);
    user = auth.user;
    db = auth.db;
    userId = user.id;
  } catch (e) {
    errorCode = "AUTH_ERROR";
    if (e instanceof AuthError) {
      status = e.status;
      return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
    }
    status = 500;
    return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
  }

  // ── 1b. Rate limit ──────────────────────────────────────────────
  const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 10, windowSeconds: 60 }, requestId);
  if (!rl.allowed) {
    status = rl.status!;
    if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
    return rl.response!;
  }

  // ── 2. Parse body ──────────────────────────────────────────────────
  let body: { challenge_id?: string } = {};
  try {
    body = await requireJson(req) as typeof body;
  } catch (e) {
    status = 400;
    if (e instanceof ValidationError) {
      return jsonErr(400, e.code, e.message, requestId);
    }
    return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
  }

  // ── 2b. Require challenge_id ──────────────────────────────────────
  try {
    requireFields(body as Record<string, unknown>, ["challenge_id"]);
  } catch (e) {
    status = 422;
    if (e instanceof ValidationError) {
      return jsonErr(422, e.code, e.message, requestId);
    }
    return jsonErr(422, "MISSING_FIELDS", "Missing required fields", requestId);
  }

  const nowMs = Date.now();

  // ── 2c. Active challenges per-user guard (DECISAO 052: max 5 active) ──
  const { data: userActiveChallenges } = await db
    .from("challenge_participants")
    .select("challenge_id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .eq("status", "accepted");

  const activeCount = userActiveChallenges?.length ?? 0;

  // Find challenges to settle
  let query = db.from("challenges").select("*").in("status", ["active", "completing"]);
  if (body.challenge_id) {
    query = query.eq("id", body.challenge_id);
  } else {
    query = query.lte("ends_at_ms", nowMs);
  }

  const { data: challenges, error } = await query;
  if (error) {
    const classified = classifyError(error);
    status = classified.httpStatus;
    errorCode = classified.code;
    return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
  }
  if (!challenges || challenges.length === 0) {
    return jsonOk({ status: "no_challenges_to_settle", settled: 0 }, requestId);
  }

  let settled = 0;

  for (const ch of challenges as Challenge[]) {
    const { data: participants } = await db
      .from("challenge_participants")
      .select("*")
      .eq("challenge_id", ch.id)
      .eq("status", "accepted");

    if (!participants || participants.length === 0) {
      await db.from("challenges").update({ status: "expired" }).eq("id", ch.id);
      continue;
    }

    const parts = participants as Participant[];
    const isLowerBetter = ch.metric === "pace";

    // Sort: primary by progress_value, secondary by last_submitted_at_ms (earlier wins ties)
    parts.sort((a, b) => {
      const diff = isLowerBetter
        ? a.progress_value - b.progress_value
        : b.progress_value - a.progress_value;
      if (diff !== 0) return diff;
      return (a.last_submitted_at_ms ?? Infinity) - (b.last_submitted_at_ms ?? Infinity);
    });

    // Assign ranks (dense ranking)
    let currentRank = 1;
    for (let i = 0; i < parts.length; i++) {
      if (i > 0 && parts[i].progress_value !== parts[i - 1].progress_value) {
        currentRank = i + 1;
      }
      (parts[i] as any)._rank = currentRank;
    }

    // Lookup coaching groups for cross-assessoria detection
    const partUserIds = parts.map((p) => p.user_id);
    const { data: profileRows } = await db
      .from("profiles")
      .select("id, active_coaching_group_id")
      .in("id", partUserIds);

    const groupByUser = new Map<string, string | null>();
    for (const row of (profileRows ?? []) as ProfileGroup[]) {
      groupByUser.set(row.id, row.active_coaching_group_id);
    }

    const allSameGroup = (() => {
      const groups = new Set(partUserIds.map((uid) => groupByUser.get(uid)));
      if (groups.size !== 1) return false;
      const single = [...groups][0];
      return single != null; // null means no group — treat as same-assessoria (individual)
    })();

    const isOneVsOne = ch.type === "one_vs_one";
    const pool = ch.entry_fee_coins * parts.length;

    const results: Record<string, unknown>[] = [];
    const ledgerEntries: Record<string, unknown>[] = [];
    const pendingEntries: Record<string, unknown>[] = [];

    const isTeamVsTeam = ch.type === "team_vs_team";

    // For team_vs_team, compute team aggregate scores using participant.team ('A' or 'B')
    let winningTeam: string | null = null;
    let isTie = false;
    if (isTeamVsTeam) {
      const teamATotal = parts
        .filter((p) => p.team === "A")
        .reduce((s, p) => s + p.progress_value, 0);
      const teamBTotal = parts
        .filter((p) => p.team === "B")
        .reduce((s, p) => s + p.progress_value, 0);

      if (ch.metric === "pace") {
        const teamACount = parts.filter((p) => p.team === "A" && p.progress_value > 0).length;
        const teamBCount = parts.filter((p) => p.team === "B" && p.progress_value > 0).length;
        const avgA = teamACount > 0 ? teamATotal / teamACount : Infinity;
        const avgB = teamBCount > 0 ? teamBTotal / teamBCount : Infinity;
        if (avgA === avgB) { isTie = true; }
        else { winningTeam = avgA < avgB ? "A" : "B"; }
      } else {
        if (teamATotal === teamBTotal) { isTie = true; }
        else { winningTeam = teamATotal > teamBTotal ? "A" : "B"; }
      }
    }

    for (const p of parts) {
      const rank = (p as any)._rank as number;
      let outcome: string;
      let coins = 0;

      if (p.progress_value <= 0 || p.contributing_session_ids.length === 0) {
        outcome = "did_not_finish";
      } else if (isTeamVsTeam) {
        if (isTie) {
          outcome = "tied";
          coins = 30 + Math.floor(pool / parts.length);
        } else if (p.team === winningTeam) {
          outcome = "won";
          const winnersCount = parts.filter((x) => x.team === winningTeam && x.progress_value > 0).length;
          coins = 30 + 15 + Math.floor(pool / (winnersCount || 1));
        } else {
          outcome = "lost";
          coins = 30;
        }
      } else if (isOneVsOne) {
        if (rank === 1) {
          outcome = "won";
          coins = 25 + 15 + pool;
        } else if (parts.filter((x) => (x as any)._rank === 1).length > 1) {
          outcome = "tied";
          coins = 25 + Math.floor(pool / parts.filter((x) => (x as any)._rank === 1).length);
        } else {
          outcome = "lost";
          coins = 25;
        }
      } else {
        if (ch.target != null && p.progress_value >= ch.target) {
          outcome = "completed_target";
          coins = 30;
        } else {
          outcome = "participated";
          coins = 10;
        }
      }

      results.push({
        challenge_id: ch.id,
        user_id: p.user_id,
        final_value: p.progress_value,
        rank,
        outcome,
        coins_earned: coins,
        session_ids: p.contributing_session_ids,
        calculated_at_ms: nowMs,
      });

      if (coins > 0) {
        // Cross-assessoria prizes: pool portion goes to pending_coins (requires clearing)
        // 1v1: cross when participants are from different groups
        // team_vs_team: cross ONLY when team_a and team_b are from different groups
        //   (intra-assessoria team challenges go directly to balance)
        const isTeamCrossGroup = isTeamVsTeam &&
          ch.team_a_group_id != null &&
          ch.team_b_group_id != null &&
          ch.team_a_group_id !== ch.team_b_group_id;

        const isCrossPrize = (
          (isOneVsOne && !allSameGroup) ||
          isTeamCrossGroup
        ) && (outcome === "won" || outcome === "tied") && pool > 0;

        if (isCrossPrize) {
          // Participation + bonus go immediately; pool portion goes to pending
          const immediateCoins = isOneVsOne
            ? 25
            : outcome === "won" ? 45 : 30; // team: 30 participation + 15 win bonus (if won)
          const pendingCoins = coins - immediateCoins;

          const immediateReason = isOneVsOne
            ? "challenge_one_vs_one_completed"
            : outcome === "won"
              ? "challenge_team_won"
              : "challenge_team_completed";

          ledgerEntries.push({
            user_id: p.user_id,
            delta_coins: immediateCoins,
            reason: immediateReason,
            ref_id: ch.id,
            created_at_ms: nowMs,
          });

          if (pendingCoins > 0) {
            pendingEntries.push({
              user_id: p.user_id,
              delta_coins: pendingCoins,
              reason: "challenge_prize_pending",
              ref_id: ch.id,
              created_at_ms: nowMs,
            });
          }
        } else {
          const reason = isOneVsOne
            ? (outcome === "won" ? "challenge_one_vs_one_won" : "challenge_one_vs_one_completed")
            : isTeamVsTeam
              ? (outcome === "won" ? "challenge_team_won" : "challenge_team_completed")
              : "challenge_group_completed";

          ledgerEntries.push({
            user_id: p.user_id,
            delta_coins: coins,
            reason,
            ref_id: ch.id,
            created_at_ms: nowMs,
          });
        }
      }
    }

    // ── Stake distribution guard (DECISAO 052) ──────────────────────
    const MAX_COINS_PER_CHALLENGE = 10_000;
    const totalCoinsOut = [...ledgerEntries, ...pendingEntries]
      .reduce((sum, e) => sum + (e.delta_coins as number), 0);
    if (totalCoinsOut > MAX_COINS_PER_CHALLENGE) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: FN,
        challenge_id: ch.id,
        error_code: "STAKE_LIMIT_EXCEEDED",
        detail: `Total coins ${totalCoinsOut} exceeds cap ${MAX_COINS_PER_CHALLENGE}`,
      }));
      await db.from("challenges").update({ status: "expired" }).eq("id", ch.id);
      continue;
    }

    // Batch writes
    await db.from("challenge_results").upsert(results, { onConflict: "challenge_id,user_id" });

    // Immediate prizes → balance_coins
    if (ledgerEntries.length > 0) {
      await db.from("coin_ledger").insert(ledgerEntries);
      for (const entry of ledgerEntries) {
        await db.rpc("increment_wallet_balance", {
          p_user_id: entry.user_id,
          p_delta: entry.delta_coins,
        });
      }
    }

    // Cross-assessoria pending prizes → pending_coins
    if (pendingEntries.length > 0) {
      await db.from("coin_ledger").insert(pendingEntries);
      for (const entry of pendingEntries) {
        await db.rpc("increment_wallet_pending", {
          p_user_id: entry.user_id,
          p_delta: entry.delta_coins,
        });
      }
    }

    await db.from("challenges").update({ status: "completed" }).eq("id", ch.id);
    settled++;
  }

  return jsonOk({ status: "ok", settled }, requestId);
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
