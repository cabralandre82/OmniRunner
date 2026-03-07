import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * league-snapshot — Supabase Edge Function
 *
 * Calculates weekly scores for all enrolled assessorias in the active
 * league season. Called by lifecycle-cron (weekly) or manually.
 *
 * Score formula (per assessoria, per week):
 *   score = (total_km * 1.0 + total_sessions * 0.5
 *            + pct_active * 200 + challenge_wins * 3.0) / num_members
 *
 * Auth: service-role key only.
 *
 * POST /league-snapshot
 */

const FN = "league-snapshot";

function isoWeekKey(d: Date): string {
  const jan4 = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
  const dayOfYear = Math.floor((d.getTime() - jan4.getTime()) / 86400000) + 4;
  const weekNum = Math.ceil(dayOfYear / 7);
  return `${d.getUTCFullYear()}-W${String(weekNum).padLeft(2, "0")}`;
}

// Polyfill padLeft for Deno
if (!(String.prototype as unknown as Record<string, unknown>).padLeft) {
  // deno-lint-ignore no-explicit-any
  (String.prototype as any).padLeft = String.prototype.padStart;
}

function getWeekRange(d: Date): { startMs: number; endMs: number } {
  const day = d.getUTCDay();
  const diff = day === 0 ? 6 : day - 1;
  const monday = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - diff));
  monday.setUTCHours(0, 0, 0, 0);
  const sunday = new Date(monday.getTime() + 6 * 86400000 + 86400000 - 1);
  return { startMs: monday.getTime(), endMs: sunday.getTime() };
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '2.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
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
    const weekKey = isoWeekKey(now);
    const { startMs, endMs } = getWeekRange(now);

    // Find active season
    const { data: season } = await db
      .from("league_seasons")
      .select("id")
      .eq("status", "active")
      .maybeSingle();

    if (!season) {
      return jsonOk({ message: "No active league season", snapshots: 0 }, requestId);
    }

    // Auto-enroll all approved assessorias not yet enrolled
    let autoEnrolled = 0;
    {
      const { data: approvedGroups } = await db
        .from("coaching_groups")
        .select("id")
        .eq("approval_status", "approved");

      const { data: existingEnrollments } = await db
        .from("league_enrollments")
        .select("group_id")
        .eq("season_id", season.id);

      const enrolledIds = new Set(
        (existingEnrollments ?? []).map((e: { group_id: string }) => e.group_id),
      );

      const toEnroll = (approvedGroups ?? []).filter(
        (g: { id: string }) => !enrolledIds.has(g.id),
      );

      for (const g of toEnroll) {
        const { error } = await db
          .from("league_enrollments")
          .insert({ season_id: season.id, group_id: g.id })
          .select()
          .maybeSingle();
        if (!error) autoEnrolled++;
      }
    }

    // Get enrolled groups (including newly auto-enrolled)
    const { data: enrollments } = await db
      .from("league_enrollments")
      .select("group_id")
      .eq("season_id", season.id);

    if (!enrollments || enrollments.length === 0) {
      return jsonOk({ message: "No enrolled groups", snapshots: 0, auto_enrolled: autoEnrolled }, requestId);
    }

    // Get previous week's rankings for rank delta
    const prevSnapshots: Record<string, number> = {};
    {
      const { data: prev } = await db
        .from("league_snapshots")
        .select("group_id, rank")
        .eq("season_id", season.id)
        .neq("week_key", weekKey)
        .order("created_at_ms", { ascending: false })
        .limit(enrollments.length);

      for (const s of prev ?? []) {
        if (!prevSnapshots[s.group_id]) {
          prevSnapshots[s.group_id] = s.rank;
        }
      }
    }

    // Calculate scores via single SQL aggregation (replaces N+1 per-group queries)
    interface GroupScore {
      groupId: string;
      totalKm: number;
      totalSessions: number;
      activeMembers: number;
      totalMembers: number;
      challengeWins: number;
      weekScore: number;
    }

    const { data: rpcRows, error: rpcErr } = await db.rpc("fn_compute_league_snapshots", {
      p_season_id: season.id,
      p_window_start_ms: startMs,
      p_window_end_ms: endMs,
    });

    if (rpcErr) throw rpcErr;

    // Fetch total member counts per group for the score formula
    const enrolledGroupIds = enrollments.map((e: { group_id: string }) => e.group_id);
    const { data: memberCounts } = await db
      .from("coaching_members")
      .select("group_id")
      .in("group_id", enrolledGroupIds)
      .eq("role", "athlete");

    const memberCountMap: Record<string, number> = {};
    for (const m of memberCounts ?? []) {
      memberCountMap[m.group_id] = (memberCountMap[m.group_id] ?? 0) + 1;
    }

    const groupScores: GroupScore[] = [];

    for (const row of rpcRows ?? []) {
      const groupId = row.group_id as string;
      const totalKm = Number(row.total_distance_m ?? 0) / 1000;
      const totalSessions = Number(row.total_sessions ?? 0);
      const activeMembers = Number(row.active_members ?? 0);
      const challengeWins = Number(row.challenge_wins ?? 0);
      const totalMembers = memberCountMap[groupId] ?? 0;

      if (totalMembers === 0) continue;

      const pctActive = activeMembers / totalMembers;
      const weekScore = (totalKm * 1.0 + totalSessions * 0.5 + pctActive * 200 + challengeWins * 3.0) / totalMembers;

      groupScores.push({
        groupId,
        totalKm: Math.round(totalKm * 100) / 100,
        totalSessions,
        activeMembers,
        totalMembers,
        challengeWins,
        weekScore: Math.round(weekScore * 100) / 100,
      });
    }

    // Get cumulative scores from previous snapshots (sum of all week_scores)
    const cumulativeMap: Record<string, number> = {};
    {
      const { data: allPrev } = await db
        .from("league_snapshots")
        .select("group_id, week_score")
        .eq("season_id", season.id)
        .neq("week_key", weekKey);

      for (const s of allPrev ?? []) {
        cumulativeMap[s.group_id] = (cumulativeMap[s.group_id] ?? 0) + s.week_score;
      }
    }

    // Sort by cumulative + this week's score
    const ranked = groupScores
      .map((g) => ({
        ...g,
        cumulativeScore: Math.round(((cumulativeMap[g.groupId] ?? 0) + g.weekScore) * 100) / 100,
      }))
      .sort((a, b) => b.cumulativeScore - a.cumulativeScore);

    // Upsert snapshots
    let snapshots = 0;
    for (let i = 0; i < ranked.length; i++) {
      const g = ranked[i];
      const rank = i + 1;

      const { error } = await db
        .from("league_snapshots")
        .upsert({
          season_id: season.id,
          group_id: g.groupId,
          week_key: weekKey,
          total_km: g.totalKm,
          total_sessions: g.totalSessions,
          active_members: g.activeMembers,
          total_members: g.totalMembers,
          challenge_wins: g.challengeWins,
          week_score: g.weekScore,
          cumulative_score: g.cumulativeScore,
          rank,
          prev_rank: prevSnapshots[g.groupId] ?? null,
          created_at_ms: Date.now(),
        }, { onConflict: "season_id,group_id,week_key" });

      if (!error) {
        snapshots++;

        // Push notification for rank changes
        const prevRank = prevSnapshots[g.groupId];
        if (prevRank != null && prevRank !== rank) {
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
                  rule: "league_rank_change",
                  context: {
                    group_id: g.groupId,
                    new_rank: rank,
                    old_rank: prevRank,
                    season_name: season.name,
                  },
                }),
                signal: AbortSignal.timeout(15_000),
              }).catch(() => {});
            }
          } catch { /* fire-and-forget */ }
        }
      }
    }

    return jsonOk({
      season_id: season.id,
      week_key: weekKey,
      snapshots,
      groups_processed: ranked.length,
      auto_enrolled: autoEnrolled,
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
