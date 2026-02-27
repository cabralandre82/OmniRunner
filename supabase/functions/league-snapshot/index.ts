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

    // Calculate scores for each group
    interface GroupScore {
      groupId: string;
      totalKm: number;
      totalSessions: number;
      activeMembers: number;
      totalMembers: number;
      challengeWins: number;
      weekScore: number;
    }

    const groupScores: GroupScore[] = [];

    for (const enrollment of enrollments) {
      const groupId = enrollment.group_id;

      // Members of this group
      const { data: members } = await db
        .from("coaching_members")
        .select("user_id")
        .eq("group_id", groupId);

      const memberIds = (members ?? []).map((m: { user_id: string }) => m.user_id);
      const totalMembers = memberIds.length;

      if (totalMembers === 0) continue;

      // Sessions this week
      let totalDistanceM = 0;
      let totalSessions = 0;
      const activeUserIds = new Set<string>();

      if (memberIds.length > 0) {
        const { data: sessions } = await db
          .from("sessions")
          .select("user_id, total_distance_m")
          .in("user_id", memberIds)
          .eq("status", 2)
          .eq("is_verified", true)
          .gte("start_time_ms", startMs)
          .lte("start_time_ms", endMs);

        for (const s of sessions ?? []) {
          totalDistanceM += s.total_distance_m ?? 0;
          totalSessions++;
          activeUserIds.add(s.user_id);
        }
      }

      const totalKm = totalDistanceM / 1000;
      const activeMembers = activeUserIds.size;
      const pctActive = totalMembers > 0 ? activeMembers / totalMembers : 0;

      // Challenge wins this week
      let challengeWins = 0;
      if (memberIds.length > 0) {
        const { data: wins } = await db
          .from("challenge_results")
          .select("id")
          .in("user_id", memberIds)
          .in("outcome", ["won", "completed_target"])
          .gte("calculated_at_ms", startMs)
          .lte("calculated_at_ms", endMs);

        challengeWins = (wins ?? []).length;
      }

      const weekScore = totalMembers > 0
        ? (totalKm * 1.0 + totalSessions * 0.5 + pctActive * 200 + challengeWins * 3.0) / totalMembers
        : 0;

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
