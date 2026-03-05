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
 * Settles completed/expired challenges: computes results, distributes rewards.
 *
 * Goal-based winner logic:
 *   - fastest_at_distance: lowest progress_value (elapsed time) wins
 *   - most_distance: highest progress_value (total meters) wins
 *   - best_pace_at_distance: lowest progress_value (pace sec/km) wins
 *   - collective_distance: group cooperative — sum of all progress toward target
 *
 * POST /settle-challenge
 * Body: { challenge_id: string }
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
  goal: string;
  target: number | null;
  entry_fee_coins: number;
  ends_at_ms: number | null;
}

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
  const FN = "settle-challenge";
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
  if (req.method !== "POST") {
    status = 405;
    return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
  }

  let user: { id: string; [key: string]: unknown };
  // deno-lint-ignore no-explicit-any
  let db: any;
  // deno-lint-ignore no-explicit-any
  let adminDb: any;
  try {
    const auth = await requireUser(req);
    user = auth.user;
    db = auth.db;
    adminDb = auth.adminDb;
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

  const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 10, windowSeconds: 60 }, requestId);
  if (!rl.allowed) {
    status = rl.status!;
    if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
    return rl.response!;
  }

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

  let query = db.from("challenges").select("*").eq("status", "active");
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

    // Race condition guard: atomically claim this challenge for settlement.
    // If another process already set status='completed', skip.
    const { data: claimed } = await db
      .from("challenges")
      .update({ status: "completing" })
      .eq("id", ch.id)
      .eq("status", "active")
      .select("id");

    if (!claimed || claimed.length === 0) {
      continue;
    }

    // Double-write guard: if results already exist, just finalize status
    const { data: existingResults } = await db
      .from("challenge_results")
      .select("challenge_id")
      .eq("challenge_id", ch.id)
      .limit(1);

    if (existingResults && existingResults.length > 0) {
      await db.from("challenges").update({ status: "completed" }).eq("id", ch.id);
      settled++;
      continue;
    }

    // M17 fix: re-fetch participants after atomic claim to exclude anyone
    // who withdrew between the initial query and this point.
    const { data: freshParticipants } = await db
      .from("challenge_participants")
      .select("*")
      .eq("challenge_id", ch.id)
      .eq("status", "accepted");

    if (!freshParticipants || freshParticipants.length === 0) {
      await db.from("challenges").update({ status: "expired" }).eq("id", ch.id);
      continue;
    }

    const parts = freshParticipants as Participant[];
    const goal = ch.goal ?? "most_distance";
    const lowerIsBetter = goal === "fastest_at_distance" || goal === "best_pace_at_distance";

    // Verification check for staked challenges
    const verifiedSet = new Set<string>();
    if (ch.entry_fee_coins > 0) {
      const partIds = parts.map((p) => p.user_id);
      const { data: verRows } = await db
        .from("athlete_verification")
        .select("user_id")
        .in("user_id", partIds)
        .eq("verification_status", "VERIFIED");
      for (const v of (verRows ?? []) as { user_id: string }[]) {
        verifiedSet.add(v.user_id);
      }
    }

    const results: Record<string, unknown>[] = [];
    const ledgerEntries: Record<string, unknown>[] = [];

    // Pool = actual collected fees from coin_ledger (not theoretical)
    let pool = 0;
    if (ch.entry_fee_coins > 0) {
      const { data: feeRows } = await db
        .from("coin_ledger")
        .select("delta_coins")
        .eq("ref_id", ch.id)
        .eq("reason", "challenge_entry_fee");

      if (feeRows && feeRows.length > 0) {
        pool = Math.abs(
          (feeRows as { delta_coins: number }[])
            .reduce((s, r) => s + r.delta_coins, 0),
        );
      }
    }

    const isOneVsOne = ch.type === "one_vs_one";
    const isTeam = ch.type === "team";
    const isCollective = goal === "collective_distance";

    if (isTeam) {
      // ── Team vs Team: aggregate per team, winning team splits pool ──
      const teamA = parts.filter((p) => p.team === "A");
      const teamB = parts.filter((p) => p.team === "B");
      const runnersA = teamA.filter((p) => (p.contributing_session_ids?.length ?? 0) > 0);
      const runnersB = teamB.filter((p) => (p.contributing_session_ids?.length ?? 0) > 0);

      if (runnersA.length === 0 && runnersB.length === 0) {
        const refundPerUser = parts.length > 0
          ? Math.floor(pool / parts.length)
          : 0;

        for (const p of parts) {
          results.push({
            challenge_id: ch.id, user_id: p.user_id,
            final_value: 0, rank: null, outcome: "did_not_finish",
            coins_earned: refundPerUser,
            session_ids: p.contributing_session_ids, calculated_at_ms: nowMs,
          });

          if (refundPerUser > 0) {
            ledgerEntries.push({
              user_id: p.user_id, delta_coins: refundPerUser,
              reason: "challenge_entry_refund", ref_id: ch.id,
              created_at_ms: nowMs,
            });
          }
        }
      } else {
        const computeTeamScore = (runners: Participant[], teamSize: number): number => {
          if (runners.length === 0) return lowerIsBetter ? Infinity : 0;
          if (goal === "fastest_at_distance") {
            return runners.length < teamSize
              ? Infinity
              : Math.max(...runners.map((p) => p.progress_value));
          } else if (goal === "most_distance") {
            return runners.reduce((s, p) => s + p.progress_value, 0);
          } else {
            return runners.reduce((s, p) => s + p.progress_value, 0) / runners.length;
          }
        };

        const scoreA = computeTeamScore(runnersA, teamA.length);
        const scoreB = computeTeamScore(runnersB, teamB.length);

        let teamAWins: boolean;
        let isTied: boolean;

        if (runnersA.length === 0) {
          teamAWins = false; isTied = false;
        } else if (runnersB.length === 0) {
          teamAWins = true; isTied = false;
        } else {
          const cmp = lowerIsBetter ? scoreA - scoreB : scoreB - scoreA;
          if (cmp < 0) { teamAWins = true; isTied = false; }
          else if (cmp > 0) { teamAWins = false; isTied = false; }
          else { teamAWins = false; isTied = true; }
        }

        for (const p of parts) {
          const isA = p.team === "A";
          const myTeamWon = isA ? teamAWins : (!teamAWins && !isTied);

          let outcome: string;
          let coins = 0;

          if (isTied) {
            outcome = "tied";
            coins = ch.entry_fee_coins > 0 ? ch.entry_fee_coins : 0;
          } else if (myTeamWon) {
            outcome = "won";
            const winnerCount = isA ? teamA.length : teamB.length;
            coins = pool > 0 && winnerCount > 0 ? Math.floor(pool / winnerCount) : 0;
          } else {
            outcome = "lost";
          }

          if (ch.entry_fee_coins > 0 && !verifiedSet.has(p.user_id) && coins > 0) {
            coins = 0;
          }

          results.push({
            challenge_id: ch.id, user_id: p.user_id,
            final_value: p.progress_value, rank: null, outcome,
            coins_earned: coins, session_ids: p.contributing_session_ids,
            calculated_at_ms: nowMs,
          });

          if (coins > 0) {
            ledgerEntries.push({
              user_id: p.user_id, delta_coins: coins,
              reason: outcome === "won" ? "challenge_team_won" : "challenge_group_completed",
              ref_id: ch.id,
              created_at_ms: nowMs,
            });
          }
        }
      }
    } else if (isCollective) {
      // ── Cooperative: sum all contributions toward target ──
      const runners = parts.filter((p) => (p.contributing_session_ids?.length ?? 0) > 0);

      if (runners.length === 0) {
        const refundPerUser = parts.length > 0
          ? Math.floor(pool / parts.length)
          : 0;

        for (const p of parts) {
          results.push({
            challenge_id: ch.id, user_id: p.user_id,
            final_value: 0, rank: null, outcome: "did_not_finish",
            coins_earned: refundPerUser,
            session_ids: p.contributing_session_ids, calculated_at_ms: nowMs,
          });

          if (refundPerUser > 0) {
            ledgerEntries.push({
              user_id: p.user_id, delta_coins: refundPerUser,
              reason: "challenge_entry_refund", ref_id: ch.id,
              created_at_ms: nowMs,
            });
          }
        }
      } else {
        const totalDistance = runners.reduce((s, p) => s + p.progress_value, 0);
        const metTarget = ch.target == null || totalDistance >= ch.target;

        for (const p of parts) {
          const outcome = metTarget ? "completed_target" : "participated";
          const coins = metTarget && pool > 0 ? Math.floor(pool / parts.length) : 0;

          results.push({
            challenge_id: ch.id, user_id: p.user_id,
            final_value: p.progress_value, rank: null, outcome,
            coins_earned: coins, session_ids: p.contributing_session_ids,
            calculated_at_ms: nowMs,
          });

          if (coins > 0) {
            ledgerEntries.push({
              user_id: p.user_id, delta_coins: coins,
              reason: "challenge_group_completed", ref_id: ch.id,
              created_at_ms: nowMs,
            });
          }
        }
      }
    } else {
      // ── Competitive: 1v1 or group ranking ──
      const anyoneRan = parts.some(
        (p) => (p.contributing_session_ids?.length ?? 0) > 0,
      );

      if (!anyoneRan && pool > 0) {
        const refundPerUser = Math.floor(pool / parts.length);
        for (const p of parts) {
          results.push({
            challenge_id: ch.id, user_id: p.user_id,
            final_value: 0, rank: null, outcome: "did_not_finish",
            coins_earned: refundPerUser,
            session_ids: p.contributing_session_ids, calculated_at_ms: nowMs,
          });
          if (refundPerUser > 0) {
            ledgerEntries.push({
              user_id: p.user_id, delta_coins: refundPerUser,
              reason: "challenge_entry_refund", ref_id: ch.id,
              created_at_ms: nowMs,
            });
          }
        }
        // Skip ranking — go straight to write
        await db.from("challenge_results").upsert(results, { onConflict: "challenge_id,user_id" });
        if (ledgerEntries.length > 0) {
          await adminDb.rpc("fn_increment_wallets_batch", {
            p_entries: ledgerEntries.map((entry) => ({
              user_id: entry.user_id,
              delta: entry.delta_coins,
              reason: entry.reason,
              ref_id: entry.ref_id,
              group_id: entry.issuer_group_id ?? null,
            })),
          });
        }
        await db.from("challenges").update({ status: "completed" }).eq("id", ch.id);
        settled++;
        continue;
      }

      // Sort by progress value
      parts.sort((a, b) => {
        const diff = lowerIsBetter
          ? a.progress_value - b.progress_value
          : b.progress_value - a.progress_value;
        if (diff !== 0) return diff;
        return (a.last_submitted_at_ms ?? Infinity) - (b.last_submitted_at_ms ?? Infinity);
      });

      // Dense ranking
      let currentRank = 1;
      for (let i = 0; i < parts.length; i++) {
        if (i > 0 && parts[i].progress_value !== parts[i - 1].progress_value) {
          currentRank = i + 1;
        }
        // deno-lint-ignore no-explicit-any
        (parts[i] as any)._rank = currentRank;
      }

      for (const p of parts) {
        // deno-lint-ignore no-explicit-any
        const rank = (p as any)._rank as number;
        const didRun = (p.contributing_session_ids?.length ?? 0) > 0;
        let outcome: string;
        let coins = 0;

        if (!didRun) {
          outcome = "did_not_finish";
        } else if (isOneVsOne) {
          const winnersCount = parts.filter(
            // deno-lint-ignore no-explicit-any
            (x) => (x as any)._rank === 1 && (x.contributing_session_ids?.length ?? 0) > 0,
          ).length;

          if (rank === 1 && winnersCount > 1) {
            outcome = "tied";
            coins = pool > 0 ? Math.floor(pool / winnersCount) : 0;
          } else if (rank === 1) {
            outcome = "won";
            coins = pool > 0 ? pool : 0;
          } else {
            outcome = "lost";
          }
        } else {
          // Group competitive
          if (rank === 1) {
            const winnersCount = parts.filter(
              // deno-lint-ignore no-explicit-any
              (x) => (x as any)._rank === 1 && (x.contributing_session_ids?.length ?? 0) > 0,
            ).length;
            outcome = winnersCount > 1 ? "tied" : "won";
            coins = pool > 0 ? Math.floor(pool / winnersCount) : 0;
          } else {
            outcome = "participated";
          }
        }

        // Stake eligibility: unverified players forfeit pool winnings
        if (ch.entry_fee_coins > 0 && !verifiedSet.has(p.user_id) && coins > 0) {
          console.log(JSON.stringify({
            request_id: requestId, fn: FN, event: "pool_forfeited",
            challenge_id: ch.id, user_id: p.user_id,
            original_coins: coins, capped_coins: 0,
            reason: "ATHLETE_NOT_VERIFIED_AT_SETTLE",
          }));
          coins = 0;
        }

        results.push({
          challenge_id: ch.id, user_id: p.user_id,
          final_value: p.progress_value, rank, outcome,
          coins_earned: coins, session_ids: p.contributing_session_ids,
          calculated_at_ms: nowMs,
        });

        if (coins > 0) {
          const reason = isOneVsOne
            ? (outcome === "won" ? "challenge_one_vs_one_won" : "challenge_one_vs_one_completed")
            : "challenge_group_completed";

          ledgerEntries.push({
            user_id: p.user_id, delta_coins: coins,
            reason, ref_id: ch.id,
            created_at_ms: nowMs,
          });
        }
      }
    }

    // Stake cap guard
    const MAX_COINS_PER_CHALLENGE = 10_000;
    const totalCoinsOut = ledgerEntries.reduce(
      (sum, e) => sum + (e.delta_coins as number), 0,
    );
    if (totalCoinsOut > MAX_COINS_PER_CHALLENGE) {
      console.error(JSON.stringify({
        request_id: requestId, fn: FN, challenge_id: ch.id,
        error_code: "STAKE_LIMIT_EXCEEDED",
        detail: `Total coins ${totalCoinsOut} exceeds cap ${MAX_COINS_PER_CHALLENGE}`,
      }));
      await db.from("challenges").update({ status: "expired" }).eq("id", ch.id);
      continue;
    }

    // Write results
    await db.from("challenge_results").upsert(results, { onConflict: "challenge_id,user_id" });

    if (ledgerEntries.length > 0) {
      await adminDb.rpc("fn_increment_wallets_batch", {
        p_entries: ledgerEntries.map((entry) => ({
          user_id: entry.user_id,
          delta: entry.delta_coins,
          reason: entry.reason,
          ref_id: entry.ref_id,
          group_id: entry.issuer_group_id ?? null,
        })),
      });
    }

    await db.from("challenges").update({ status: "completed" }).eq("id", ch.id);

    // Push notification
    try {
      const svcKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
      const svcUrl = Deno.env.get("SUPABASE_URL");
      if (svcKey && svcUrl) {
        fetch(`${svcUrl}/functions/v1/notify-rules`, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${svcKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            rule: "challenge_settled",
            context: { challenge_id: ch.id },
          }),
          signal: AbortSignal.timeout(15_000),
        }).catch(() => {});
      }
    } catch { /* fire-and-forget */ }

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
