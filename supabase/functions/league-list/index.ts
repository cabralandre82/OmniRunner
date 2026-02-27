import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * league-list — Supabase Edge Function
 *
 * Returns the active league season ranking plus the caller's assessoria
 * position and personal contribution.
 *
 * GET /league-list?scope=global          (default — all groups)
 * GET /league-list?scope=state           (filter by caller's state)
 * GET /league-list?scope=state&state=SP  (filter by specific state)
 *
 * Returns:
 *   - season: { id, name, start_at_ms, end_at_ms, status }
 *   - scope: "global" | "state"
 *   - state_filter: string | null
 *   - ranking: [{ group_id, group_name, logo_url, rank, prev_rank,
 *                 cumulative_score, week_score, total_km, total_sessions,
 *                 active_members, total_members, state }]
 *   - my_group_id: string | null
 *   - my_contribution: { total_km, total_sessions } | null
 */

const FN = "league-list";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "GET") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use GET", requestId);
    }

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
        status = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      status = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      return rl.response!;
    }

    // Parse scope filter from query string
    const url = new URL(req.url);
    const scopeParam = url.searchParams.get("scope") ?? "global";
    let stateParam = url.searchParams.get("state")?.toUpperCase().trim() ?? null;

    // Get active season
    const { data: season } = await db
      .from("league_seasons")
      .select("id, name, start_at_ms, end_at_ms, status")
      .eq("status", "active")
      .maybeSingle();

    if (!season) {
      return jsonOk({ season: null, scope: scopeParam, state_filter: null, ranking: [], my_group_id: null, my_contribution: null }, requestId);
    }

    // Caller's assessoria (need early for state auto-detect)
    const { data: profile } = await db
      .from("profiles")
      .select("active_coaching_group_id")
      .eq("id", user.id)
      .maybeSingle();

    const myGroupId = profile?.active_coaching_group_id ?? null;

    // Auto-detect state from caller's group if scope=state and no explicit state
    if (scopeParam === "state" && !stateParam && myGroupId) {
      const { data: myGroup } = await db
        .from("coaching_groups")
        .select("state")
        .eq("id", myGroupId)
        .maybeSingle();
      stateParam = (myGroup?.state as string) || null;
    }

    const effectiveStateFilter = scopeParam === "state" ? stateParam : null;

    // Get latest snapshots for each group (latest week_key)
    const { data: latestWeek } = await db
      .from("league_snapshots")
      .select("week_key")
      .eq("season_id", season.id)
      .order("created_at_ms", { ascending: false })
      .limit(1)
      .maybeSingle();

    const weekKey = latestWeek?.week_key;

    let ranking: Record<string, unknown>[] = [];

    if (weekKey) {
      const { data: snapshots } = await db
        .from("league_snapshots")
        .select("group_id, rank, prev_rank, cumulative_score, week_score, total_km, total_sessions, active_members, total_members, challenge_wins")
        .eq("season_id", season.id)
        .eq("week_key", weekKey)
        .order("cumulative_score", { ascending: false });

      if (snapshots && snapshots.length > 0) {
        const groupIds = snapshots.map((s: Record<string, unknown>) => s.group_id);

        const { data: groups } = await db
          .from("coaching_groups")
          .select("id, name, logo_url, city, state")
          .in("id", groupIds);

        const groupMap: Record<string, Record<string, unknown>> = {};
        for (const g of groups ?? []) {
          groupMap[g.id] = g;
        }

        // Build full list, then filter by state if needed
        let allEntries = snapshots.map((s: Record<string, unknown>) => {
          const group = groupMap[s.group_id as string] ?? {};
          return {
            group_id: s.group_id,
            group_name: group.name ?? "Assessoria",
            logo_url: group.logo_url ?? null,
            city: group.city ?? null,
            state: group.state ?? null,
            cumulative_score: s.cumulative_score,
            week_score: s.week_score,
            total_km: s.total_km,
            total_sessions: s.total_sessions,
            active_members: s.active_members,
            total_members: s.total_members,
            challenge_wins: s.challenge_wins,
            // Original global rank for reference
            global_rank: s.rank,
            prev_rank: s.prev_rank,
          };
        });

        if (effectiveStateFilter) {
          allEntries = allEntries.filter(
            (e: Record<string, unknown>) =>
              (e.state as string)?.toUpperCase() === effectiveStateFilter,
          );
        }

        // Re-rank within the filtered set
        ranking = allEntries.map(
          (e: Record<string, unknown>, i: number) => ({
            ...e,
            rank: i + 1,
          }),
        );
      }
    }

    // Caller's personal contribution this season
    let myContribution: Record<string, unknown> | null = null;

    if (myGroupId) {
      const { data: mySessions } = await db
        .from("sessions")
        .select("total_distance_m")
        .eq("user_id", user.id)
        .eq("status", 2)
        .eq("is_verified", true)
        .gte("start_time_ms", season.start_at_ms)
        .lte("start_time_ms", season.end_at_ms);

      const sessions = mySessions ?? [];
      const totalKm = sessions.reduce(
        (sum: number, s: { total_distance_m: number }) => sum + (s.total_distance_m ?? 0),
        0,
      ) / 1000;

      myContribution = {
        total_km: Math.round(totalKm * 100) / 100,
        total_sessions: sessions.length,
      };
    }

    return jsonOk({
      season,
      scope: scopeParam,
      state_filter: effectiveStateFilter,
      week_key: weekKey ?? null,
      ranking,
      my_group_id: myGroupId,
      my_contribution: myContribution,
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
