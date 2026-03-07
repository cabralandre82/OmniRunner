import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * lifecycle-cron — Supabase Edge Function
 *
 * Scheduled via pg_cron (every 5 minutes). Handles:
 *   1. Championship transitions: open→active, active→completed
 *   2. Challenge settlement: active challenges past their window
 *   3. Challenge expiration: pending challenges older than 7 days
 *
 * Auth: service-role key only (called by pg_net from pg_cron).
 *
 * POST /lifecycle-cron
 * Headers: Authorization: Bearer <service_role_key>
 */

const FN = "lifecycle-cron";
const PENDING_EXPIRY_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const MAX_ELAPSED_MS = 45_000;
const SETTLE_CONCURRENCY = 5;

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
    const nowIso = now.toISOString();
    const nowMs = now.getTime();

    let champsActivated = 0;
    let champsCompleted = 0;
    let challengesSettled = 0;
    let challengesExpired = 0;

    // ── 1. Championships: open → active ──────────────────────────────────
    {
      const { data: dueOpen } = await db
        .from("championships")
        .select("id")
        .eq("status", "open")
        .lte("start_at", nowIso);

      for (const ch of dueOpen ?? []) {
        await db.from("championship_participants")
          .update({ status: "active", updated_at: nowIso })
          .eq("championship_id", ch.id)
          .eq("status", "enrolled");

        const { error } = await db.from("championships")
          .update({ status: "active", updated_at: nowIso })
          .eq("id", ch.id)
          .eq("status", "open");

        if (!error) champsActivated++;
      }
    }

    // ── 2. Championships: active → completed ─────────────────────────────
    {
      const { data: dueActive } = await db
        .from("championships")
        .select("id, metric")
        .eq("status", "active")
        .lte("end_at", nowIso);

      for (const ch of (dueActive ?? []) as { id: string; metric: string }[]) {
        const isLowerBetter = ch.metric === "pace";
        const { data: parts } = await db
          .from("championship_participants")
          .select("id, progress_value")
          .eq("championship_id", ch.id)
          .in("status", ["active", "enrolled"])
          .order("progress_value", { ascending: isLowerBetter });

        let rank = 1;
        for (let i = 0; i < (parts ?? []).length; i++) {
          if (i > 0 && parts![i].progress_value !== parts![i - 1].progress_value) {
            rank = i + 1;
          }
          await db.from("championship_participants")
            .update({ final_rank: rank, status: "completed", updated_at: nowIso })
            .eq("id", parts![i].id);
        }

        const { error } = await db.from("championships")
          .update({ status: "completed", updated_at: nowIso })
          .eq("id", ch.id)
          .eq("status", "active");

        if (!error) champsCompleted++;
      }
    }

    // ── 3. Challenges: settle expired active challenges (parallel) ───────
    {
      const { data: expiredChallenges } = await db
        .from("challenges")
        .select("id")
        .eq("status", "active")
        .lte("ends_at_ms", nowMs)
        .limit(50);

      const toSettle = expiredChallenges ?? [];

      async function settleOne(challengeId: string): Promise<boolean> {
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), 15_000);
        try {
          const res = await fetch(`${supabaseUrl}/functions/v1/settle-challenge`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${serviceKey}`,
            },
            body: JSON.stringify({ challenge_id: challengeId }),
            signal: ctrl.signal,
          });
          return res.ok;
        } catch {
          return false;
        } finally {
          clearTimeout(timer);
        }
      }

      for (let i = 0; i < toSettle.length; i += SETTLE_CONCURRENCY) {
        if (elapsed() > MAX_ELAPSED_MS) {
          console.warn(JSON.stringify({
            fn: FN, request_id: requestId,
            msg: `Elapsed ${elapsed()}ms > ${MAX_ELAPSED_MS}ms, skipping ${toSettle.length - i} remaining settle calls`,
          }));
          break;
        }
        const chunk = toSettle.slice(i, i + SETTLE_CONCURRENCY);
        const results = await Promise.allSettled(chunk.map((ch) => settleOne(ch.id)));
        for (const r of results) {
          if (r.status === "fulfilled" && r.value) challengesSettled++;
        }
      }
    }

    // ── 4. Challenges: expire stale pending challenges ───────────────────
    {
      const expiryThreshold = nowMs - PENDING_EXPIRY_MS;

      const { data: stalePending } = await db
        .from("challenges")
        .select("id")
        .eq("status", "pending")
        .lte("created_at_ms", expiryThreshold)
        .limit(100);

      for (const ch of stalePending ?? []) {
        const { error } = await db.from("challenges")
          .update({ status: "expired" })
          .eq("id", ch.id)
          .eq("status", "pending");

        if (!error) challengesExpired++;
      }
    }

    // ── 5. League snapshot (weekly, idempotent per week_key) ─────────
    const skippedPhases: string[] = [];
    let leagueSnapshot = false;
    {
      const dayOfWeek = now.getUTCDay(); // 0=Sun, 1=Mon
      if (dayOfWeek === 1 && now.getUTCHours() < 1) {
        try {
          const leagueCtrl = new AbortController();
          const leagueTimer = setTimeout(() => leagueCtrl.abort(), 15_000);
          try {
            const res = await fetch(`${supabaseUrl}/functions/v1/league-snapshot`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${serviceKey}`,
              },
              signal: leagueCtrl.signal,
            });
            leagueSnapshot = res.ok;
          } finally {
            clearTimeout(leagueTimer);
          }
        } catch {
          // Log but continue
        }
      }
    }

    // ── 6. Push: challenge expiring (< 24h left, once per cycle) ──────
    let challengeExpiringNotifs = false;
    if (elapsed() > MAX_ELAPSED_MS) {
      skippedPhases.push("challenge_expiring", "inactivity_nudge", "streak_at_risk");
    } else {
      try {
        const expCtrl = new AbortController();
        const expTimer = setTimeout(() => expCtrl.abort(), 15_000);
        try {
          const res = await fetch(`${supabaseUrl}/functions/v1/notify-rules`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${serviceKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ rule: "challenge_expiring" }),
            signal: expCtrl.signal,
          });
          challengeExpiringNotifs = res.ok;
        } finally {
          clearTimeout(expTimer);
        }
      } catch {
        // best-effort
      }
    }

    // ── 7. Push: inactivity nudge (5+ days, once daily) ───────────────
    let inactivityNudge = false;
    if (elapsed() > MAX_ELAPSED_MS) {
      if (!skippedPhases.includes("inactivity_nudge")) skippedPhases.push("inactivity_nudge", "streak_at_risk");
    } else {
      const hour = now.getUTCHours();
      if (hour >= 17 && hour < 18) {
        try {
          const nudgeCtrl = new AbortController();
          const nudgeTimer = setTimeout(() => nudgeCtrl.abort(), 15_000);
          try {
            const res = await fetch(`${supabaseUrl}/functions/v1/notify-rules`, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${serviceKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({ rule: "inactivity_nudge" }),
              signal: nudgeCtrl.signal,
            });
            inactivityNudge = res.ok;
          } finally {
            clearTimeout(nudgeTimer);
          }
        } catch {
          // best-effort
        }
      }
    }

    // ── 8. Push: streak at risk (evening, once daily) ─────────────────
    let streakAtRiskNotifs = false;
    if (elapsed() > MAX_ELAPSED_MS) {
      if (!skippedPhases.includes("streak_at_risk")) skippedPhases.push("streak_at_risk");
    } else {
      const hour = now.getUTCHours();
      if (hour >= 20 && hour < 21) {
        try {
          const streakCtrl = new AbortController();
          const streakTimer = setTimeout(() => streakCtrl.abort(), 15_000);
          try {
            const res = await fetch(`${supabaseUrl}/functions/v1/notify-rules`, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${serviceKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({ rule: "streak_at_risk" }),
              signal: streakCtrl.signal,
            });
            streakAtRiskNotifs = res.ok;
          } finally {
            clearTimeout(streakTimer);
          }
        } catch {
          // best-effort
        }
      }
    }

    if (skippedPhases.length > 0) {
      console.warn(JSON.stringify({
        fn: FN, request_id: requestId,
        msg: `Elapsed ${elapsed()}ms, skipped phases: ${skippedPhases.join(", ")}`,
      }));
    }

    return jsonOk({
      championships: { activated: champsActivated, completed: champsCompleted },
      challenges: { settled: challengesSettled, expired: challengesExpired },
      league: { snapshot_triggered: leagueSnapshot },
      push: {
        challenge_expiring: challengeExpiringNotifs,
        inactivity_nudge: inactivityNudge,
        streak_at_risk: streakAtRiskNotifs,
      },
      skipped_phases: skippedPhases.length > 0 ? skippedPhases : undefined,
      elapsed_ms: elapsed(),
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
