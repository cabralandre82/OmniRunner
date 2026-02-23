import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * clearing-cron — Supabase Edge Function
 *
 * Scheduled via pg_cron (daily 02:00 UTC). Handles:
 *   1. Aggregates unmatched challenge_prize_pending ledger entries
 *      into clearing_cases grouped by (week, losing_group → winning_group)
 *   2. Creates clearing_case_items linking individual prizes to cases
 *   3. Expires overdue clearing_cases (deadline_at < now)
 *
 * Auth: service-role key only (called by pg_net from pg_cron).
 *
 * POST /clearing-cron
 * Headers: Authorization: Bearer <service_role_key>
 */

const FN = "clearing-cron";
const DEADLINE_DAYS = 7;

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (token !== serviceKey) {
      status = 401;
      errorCode = "UNAUTHORIZED";
      return jsonErr(401, "UNAUTHORIZED", "Service role key required", requestId);
    }

    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    const now = new Date();
    let casesCreated = 0;
    let itemsCreated = 0;
    let casesExpired = 0;

    // ── 1. Find/create current clearing_week (ISO week: Monday–Sunday) ──
    const weekStart = getMonday(now);
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekEnd.getDate() + 6);

    const startStr = weekStart.toISOString().slice(0, 10);
    const endStr = weekEnd.toISOString().slice(0, 10);

    const { data: existingWeek } = await db
      .from("clearing_weeks")
      .select("id")
      .eq("start_date", startStr)
      .eq("end_date", endStr)
      .maybeSingle();

    let weekId: string;
    if (existingWeek) {
      weekId = existingWeek.id;
    } else {
      const { data: newWeek, error: weekErr } = await db
        .from("clearing_weeks")
        .insert({ start_date: startStr, end_date: endStr, status: "OPEN" })
        .select("id")
        .single();

      if (weekErr || !newWeek) {
        // Possibly a race condition; try fetching again
        const { data: retry } = await db
          .from("clearing_weeks")
          .select("id")
          .eq("start_date", startStr)
          .eq("end_date", endStr)
          .maybeSingle();
        if (!retry) {
          status = 500;
          errorCode = "WEEK_CREATE_FAILED";
          return jsonErr(500, "INTERNAL", "Failed to create clearing week", requestId);
        }
        weekId = retry.id;
      } else {
        weekId = newWeek.id;
      }
    }

    // ── 2. Find unmatched challenge_prize_pending ledger entries ─────────
    // Anti-join: pending entries whose (challenge_id, winner_user_id) combo
    // doesn't yet exist in clearing_case_items.
    const { data: pendingEntries } = await db
      .from("coin_ledger")
      .select("id, user_id, delta_coins, ref_id")
      .eq("reason", "challenge_prize_pending")
      .gt("delta_coins", 0);

    if (!pendingEntries || pendingEntries.length === 0) {
      // Skip to expiry
    } else {
      // Find which entries already have clearing_case_items
      const entryPairs = pendingEntries.map((e: { ref_id: string; user_id: string }) => ({
        challenge_id: e.ref_id,
        winner_user_id: e.user_id,
      }));

      const { data: existingItems } = await db
        .from("clearing_case_items")
        .select("challenge_id, winner_user_id");

      const existingSet = new Set(
        (existingItems ?? []).map(
          (i: { challenge_id: string; winner_user_id: string }) =>
            `${i.challenge_id}::${i.winner_user_id}`
        )
      );

      const unmatchedEntries = pendingEntries.filter(
        (e: { ref_id: string; user_id: string }) =>
          !existingSet.has(`${e.ref_id}::${e.user_id}`)
      );

      if (unmatchedEntries.length > 0) {
        // Get unique challenge_ids
        const challengeIds = [...new Set(unmatchedEntries.map((e: { ref_id: string }) => e.ref_id))];

        // Fetch challenge details
        const { data: challenges } = await db
          .from("challenges")
          .select("id, type, team_a_group_id, team_b_group_id")
          .in("id", challengeIds);

        const challengeMap = new Map(
          (challenges ?? []).map((c: { id: string; type: string; team_a_group_id: string | null; team_b_group_id: string | null }) => [c.id, c])
        );

        // Fetch all participants for these challenges (to determine groups)
        const { data: participants } = await db
          .from("challenge_participants")
          .select("challenge_id, user_id, group_id, status")
          .in("challenge_id", challengeIds)
          .eq("status", "accepted");

        // Build lookup: (challenge_id, user_id) → group_id
        const partGroupMap = new Map<string, string | null>();
        for (const p of (participants ?? []) as { challenge_id: string; user_id: string; group_id: string | null }[]) {
          partGroupMap.set(`${p.challenge_id}::${p.user_id}`, p.group_id);
        }

        // ── 3. Determine (from_group, to_group) for each entry ──────────
        interface ClearingItem {
          challengeId: string;
          winnerUserId: string;
          loserUserId: string;
          amount: number;
          fromGroupId: string;
          toGroupId: string;
        }

        const clearingItems: ClearingItem[] = [];

        for (const entry of unmatchedEntries as { id: string; user_id: string; delta_coins: number; ref_id: string }[]) {
          const ch = challengeMap.get(entry.ref_id) as { id: string; type: string; team_a_group_id: string | null; team_b_group_id: string | null } | undefined;
          if (!ch) continue;

          const winnerGroupId = partGroupMap.get(`${ch.id}::${entry.user_id}`);
          if (!winnerGroupId) continue;

          let loserGroupId: string | null = null;
          let loserUserId: string | null = null;

          if (ch.type === "team_vs_team") {
            // Losing group is the other team
            loserGroupId = winnerGroupId === ch.team_a_group_id
              ? ch.team_b_group_id
              : ch.team_a_group_id;

            // Pick representative loser: first participant from losing team
            const loser = (participants ?? []).find(
              (p: { challenge_id: string; group_id: string | null }) =>
                p.challenge_id === ch.id && p.group_id === loserGroupId
            ) as { user_id: string } | undefined;
            loserUserId = loser?.user_id ?? "unknown";
          } else {
            // 1v1: loser is the other participant
            const otherPart = (participants ?? []).find(
              (p: { challenge_id: string; user_id: string }) =>
                p.challenge_id === ch.id && p.user_id !== entry.user_id
            ) as { user_id: string; group_id: string | null } | undefined;
            loserGroupId = otherPart?.group_id ?? null;
            loserUserId = otherPart?.user_id ?? "unknown";
          }

          if (!loserGroupId || !loserUserId) continue;

          clearingItems.push({
            challengeId: ch.id,
            winnerUserId: entry.user_id,
            loserUserId,
            amount: entry.delta_coins,
            fromGroupId: loserGroupId,
            toGroupId: winnerGroupId,
          });
        }

        // ── 4. Group by (from_group, to_group) and create/update cases ──
        const groupPairs = new Map<string, ClearingItem[]>();
        for (const item of clearingItems) {
          const key = `${item.fromGroupId}::${item.toGroupId}`;
          if (!groupPairs.has(key)) groupPairs.set(key, []);
          groupPairs.get(key)!.push(item);
        }

        const deadlineAt = new Date(now.getTime() + DEADLINE_DAYS * 24 * 60 * 60 * 1000).toISOString();

        for (const [_key, items] of groupPairs) {
          const fromGroupId = items[0].fromGroupId;
          const toGroupId = items[0].toGroupId;
          const totalTokens = items.reduce((s, i) => s + i.amount, 0);

          // Check if case already exists for this week + pair
          const { data: existingCase } = await db
            .from("clearing_cases")
            .select("id, tokens_total")
            .eq("week_id", weekId)
            .eq("from_group_id", fromGroupId)
            .eq("to_group_id", toGroupId)
            .in("status", ["OPEN"])
            .maybeSingle();

          let caseId: string;
          if (existingCase) {
            caseId = existingCase.id;
            await db
              .from("clearing_cases")
              .update({
                tokens_total: existingCase.tokens_total + totalTokens,
                updated_at: new Date().toISOString(),
              })
              .eq("id", caseId);
          } else {
            const { data: newCase, error: caseErr } = await db
              .from("clearing_cases")
              .insert({
                week_id: weekId,
                from_group_id: fromGroupId,
                to_group_id: toGroupId,
                tokens_total: totalTokens,
                status: "OPEN",
                deadline_at: deadlineAt,
              })
              .select("id")
              .single();

            if (caseErr || !newCase) continue;
            caseId = newCase.id;

            await db.from("clearing_case_events").insert({
              case_id: caseId,
              actor_id: "00000000-0000-0000-0000-000000000000",
              event_type: "CREATED",
              metadata: { from_group_id: fromGroupId, to_group_id: toGroupId, week: startStr },
            });

            casesCreated++;
          }

          // Insert clearing_case_items (idempotent via unique index)
          for (const item of items) {
            const { error: itemErr } = await db
              .from("clearing_case_items")
              .insert({
                case_id: caseId,
                challenge_id: item.challengeId,
                winner_user_id: item.winnerUserId,
                loser_user_id: item.loserUserId,
                amount: item.amount,
              });

            if (!itemErr) itemsCreated++;
          }
        }
      }
    }

    // ── 5. Expire overdue clearing cases ────────────────────────────────
    {
      const { data: overdue } = await db
        .from("clearing_cases")
        .select("id")
        .in("status", ["OPEN", "SENT_CONFIRMED"])
        .lt("deadline_at", now.toISOString())
        .limit(100);

      for (const cc of overdue ?? []) {
        const { error: expErr } = await db
          .from("clearing_cases")
          .update({ status: "EXPIRED", updated_at: now.toISOString() })
          .eq("id", cc.id)
          .in("status", ["OPEN", "SENT_CONFIRMED"]);

        if (!expErr) {
          await db.from("clearing_case_events").insert({
            case_id: cc.id,
            actor_id: "00000000-0000-0000-0000-000000000000",
            event_type: "EXPIRED",
            metadata: { expired_by: "clearing-cron" },
          });
          casesExpired++;
        }
      }
    }

    return jsonOk({
      cases_created: casesCreated,
      items_created: itemsCreated,
      cases_expired: casesExpired,
    }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: null, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: null, status, duration_ms: elapsed() });
    }
  }
});

function getMonday(d: Date): Date {
  const date = new Date(d);
  date.setUTCHours(0, 0, 0, 0);
  const day = date.getUTCDay();
  const diff = day === 0 ? -6 : 1 - day;
  date.setUTCDate(date.getUTCDate() + diff);
  return date;
}
