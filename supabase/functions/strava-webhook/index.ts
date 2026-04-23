import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import {
  runAntiCheatPipeline,
  normalizeStravaActivity,
  loadAntiCheatThresholds,
  haversine,
} from "../_shared/anti_cheat.ts";
import { withCircuitBreaker } from "../_shared/circuit_breaker.ts";
import { logIntegrationEvent } from "../_shared/integration_telemetry.ts";

/**
 * strava-webhook — Supabase Edge Function
 *
 * Handles Strava Webhook Events API:
 *   GET  → subscription validation (hub.challenge response)
 *   POST → event notification (activity created/updated/deleted)
 *
 * On activity.create for type=Run:
 *   1. Look up strava_connections for the athlete
 *   2. Fetch activity details + GPS streams from Strava API
 *   3. Run anti-cheat checks on GPS data
 *   4. Create session in DB with source='strava'
 *   5. Link to active challenges if applicable
 *
 * Deployed with --no-verify-jwt (external webhook).
 *
 * Env vars:
 *   STRAVA_VERIFY_TOKEN     — shared secret for subscription validation
 *   STRAVA_CLIENT_ID        — OAuth client ID (for token refresh)
 *   STRAVA_CLIENT_SECRET    — OAuth client secret
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY / SERVICE_ROLE_KEY
 */

const FN = "strava-webhook";

serve(async (req: Request) => {
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
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY")!;

    // ── GET: Subscription validation ──────────────────────────────
    if (req.method === "GET") {
      const url = new URL(req.url);
      const mode = url.searchParams.get("hub.mode");
      const token = url.searchParams.get("hub.verify_token");
      const challenge = url.searchParams.get("hub.challenge");

      const verifyToken = Deno.env.get("STRAVA_VERIFY_TOKEN") ?? "omnirunner_strava_verify";

      if (mode === "subscribe" && token === verifyToken && challenge) {
        const telemetryDb = createClient(supabaseUrl, serviceKey, {
          auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        });
        await logIntegrationEvent(telemetryDb, {
          provider: "strava",
          event_type: "webhook_validated",
          status: "success",
          latency_ms: elapsed(),
          metadata: { request_id: requestId },
        });
        return new Response(JSON.stringify({ "hub.challenge": challenge }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }

      status = 403;
      return jsonErr(403, "INVALID_VERIFY", "Invalid subscription validation", requestId);
    }

    // ── POST: Event notification ──────────────────────────────────
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use GET or POST", requestId);
    }

    let event: {
      object_type: string;
      object_id: number;
      aspect_type: string;
      owner_id: number;
      subscription_id: number;
      event_time: number;
      updates?: Record<string, unknown>;
    };

    try {
      event = await req.json();
    } catch {
      status = 400;
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    // ── Queue-based approach: enqueue and return 200 fast ────────────
    // Strava requires fast webhook responses; heavy processing is deferred.
    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    const { error: enqueueErr } = await db
      .from("strava_event_queue")
      .insert({
        owner_id: event.owner_id,
        object_type: event.object_type,
        object_id: event.object_id,
        aspect_type: event.aspect_type,
        event_time: event.event_time,
        subscription_id: event.subscription_id ?? null,
        status: "pending",
      }, { onConflict: "owner_id,object_id,aspect_type" })
      // dedup: the unique index on (owner_id, object_id, aspect_type) prevents duplicates
      .select("id")
      .maybeSingle();

    if (enqueueErr) {
      const msg = enqueueErr.message ?? "";
      // ON CONFLICT / duplicate → already queued, still return 200
      if (msg.includes("duplicate") || msg.includes("unique") || msg.includes("conflict")) {
        await logIntegrationEvent(db, {
          provider: "strava",
          event_type: "webhook_dedup",
          status: "ignored",
          external_id: String(event.object_id),
          latency_ms: elapsed(),
          metadata: {
            owner_id: event.owner_id,
            aspect_type: event.aspect_type,
            request_id: requestId,
          },
        });
        return jsonOk({ queued: false, reason: "already_queued", owner_id: event.owner_id, object_id: event.object_id }, requestId);
      }
      console.error(JSON.stringify({ request_id: requestId, fn: FN, error_code: "ENQUEUE_FAILED", detail: msg }));
      await logIntegrationEvent(db, {
        provider: "strava",
        event_type: "webhook_received",
        status: "error",
        external_id: String(event.object_id),
        error_code: "ENQUEUE_FAILED",
        latency_ms: elapsed(),
        metadata: {
          owner_id: event.owner_id,
          aspect_type: event.aspect_type,
          request_id: requestId,
        },
      });
    } else {
      await logIntegrationEvent(db, {
        provider: "strava",
        event_type: "webhook_received",
        status: "success",
        external_id: String(event.object_id),
        latency_ms: elapsed(),
        metadata: {
          owner_id: event.owner_id,
          aspect_type: event.aspect_type,
          subscription_id: event.subscription_id ?? null,
          request_id: requestId,
        },
      });
    }

    return jsonOk({
      queued: true,
      owner_id: event.owner_id,
      object_id: event.object_id,
      aspect_type: event.aspect_type,
    }, requestId);

  } catch (err) {
    status = 500;
    errorCode = "INTERNAL";
    logError({
      request_id: requestId,
      fn: FN,
      user_id: null,
      error_code: `INTERNAL: ${(err as Error).message}`,
      duration_ms: elapsed(),
    });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: null, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: null, status, duration_ms: elapsed() });
    }
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// processStravaEvent — Contains the full processing logic.
// Designed to be called by a queue processor (separate cron/function).
// ═════════════════════════════════════════════════════════════════════════════

export async function processStravaEvent(
  db: ReturnType<typeof createClient>,
  event: { owner_id: number; object_id: number; aspect_type: string },
  requestId: string,
): Promise<{ imported: boolean; ignored?: boolean; reason?: string; session_id?: string }> {
  const stravaAthleteId = event.owner_id;
  const stravaActivityId = event.object_id;

  if (event.aspect_type !== "create") {
    await logIntegrationEvent(db, {
      provider: "strava",
      event_type: "session_ignored",
      status: "ignored",
      external_id: String(stravaActivityId),
      metadata: { reason: `aspect_${event.aspect_type}`, request_id: requestId },
    });
    return { imported: false, ignored: true, reason: `aspect_${event.aspect_type}` };
  }

  // 1. Find user by Strava athlete ID
  const { data: conn } = await db
    .from("strava_connections")
    .select("user_id, access_token, refresh_token, expires_at")
    .eq("strava_athlete_id", stravaAthleteId)
    .maybeSingle();

  if (!conn) {
    await logIntegrationEvent(db, {
      provider: "strava",
      event_type: "session_ignored",
      status: "ignored",
      external_id: String(stravaActivityId),
      metadata: {
        reason: "no_connection",
        strava_athlete_id: stravaAthleteId,
        request_id: requestId,
      },
    });
    return { imported: false, ignored: true, reason: "no_connection" };
  }

  // 2. Check for duplicate
  const { data: existing } = await db
    .from("sessions")
    .select("id")
    .eq("user_id", conn.user_id)
    .eq("strava_activity_id", stravaActivityId)
    .maybeSingle();

  if (existing) {
    await logIntegrationEvent(db, {
      provider: "strava",
      event_type: "session_ignored",
      status: "ignored",
      user_id: conn.user_id,
      external_id: String(stravaActivityId),
      metadata: { reason: "duplicate", request_id: requestId },
    });
    return { imported: false, ignored: true, reason: "duplicate" };
  }

  // 3. Get valid access token (refresh if expired)
  let accessToken = conn.access_token;
  const now = Math.floor(Date.now() / 1000);

  if (conn.expires_at < now + 300) {
    const clientId = Deno.env.get("STRAVA_CLIENT_ID");
    const clientSecret = Deno.env.get("STRAVA_CLIENT_SECRET");
    if (!clientId || !clientSecret) return { imported: false, reason: "strava_config_missing" };

    const refreshCtrl = new AbortController();
    const refreshTimer = setTimeout(() => refreshCtrl.abort(), 15_000);
    let refreshRes: Response;
    try {
      refreshRes = await withCircuitBreaker("strava-oauth", () =>
        fetch("https://www.strava.com/oauth/token", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            grant_type: "refresh_token",
            refresh_token: conn.refresh_token,
          }),
          signal: refreshCtrl.signal,
        }),
      );
    } finally {
      clearTimeout(refreshTimer);
    }

    if (!refreshRes.ok) {
      await logIntegrationEvent(db, {
        provider: "strava",
        event_type: "token_refresh_failure",
        status: "error",
        user_id: conn.user_id,
        error_code: `HTTP_${refreshRes.status}`,
        external_id: String(stravaActivityId),
        metadata: { request_id: requestId },
      });
      return { imported: false, ignored: true, reason: "token_refresh_failed" };
    }

    const tokens = await refreshRes.json();
    accessToken = tokens.access_token;

    await db
      .from("strava_connections")
      .update({
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token ?? conn.refresh_token,
        expires_at: tokens.expires_at,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", conn.user_id);

    await logIntegrationEvent(db, {
      provider: "strava",
      event_type: "token_refresh_success",
      status: "success",
      user_id: conn.user_id,
      external_id: String(stravaActivityId),
      metadata: { request_id: requestId },
    });
  }

  // 4. Fetch activity details
  const activityCtrl = new AbortController();
  const activityTimer = setTimeout(() => activityCtrl.abort(), 15_000);
  let activityRes: Response;
  try {
    activityRes = await withCircuitBreaker("strava-api", () =>
      fetch(
        `https://www.strava.com/api/v3/activities/${stravaActivityId}`,
        { headers: { Authorization: `Bearer ${accessToken}` }, signal: activityCtrl.signal },
      ),
    );
  } finally {
    clearTimeout(activityTimer);
  }

  if (!activityRes.ok) return { imported: false, ignored: true, reason: "activity_fetch_failed" };

  const activity = await activityRes.json();
  const runTypes = ["Run", "TrailRun", "VirtualRun"];
  if (!runTypes.includes(activity.type)) return { imported: false, ignored: true, reason: `type_${activity.type}` };

  // 5. Fetch GPS + HR streams
  const streamsCtrl = new AbortController();
  const streamsTimer = setTimeout(() => streamsCtrl.abort(), 15_000);
  let streamsRes: Response;
  try {
    streamsRes = await withCircuitBreaker("strava-api", () =>
      fetch(
        `https://www.strava.com/api/v3/activities/${stravaActivityId}/streams?keys=latlng,time,heartrate,velocity_smooth,altitude,cadence&key_type=time`,
        { headers: { Authorization: `Bearer ${accessToken}` }, signal: streamsCtrl.signal },
      ),
    );
  } finally {
    clearTimeout(streamsTimer);
  }

  let streams: Record<string, { data: number[] | number[][] }> = {};
  if (streamsRes.ok) {
    const raw = await streamsRes.json();
    if (Array.isArray(raw)) {
      for (const s of raw) {
        streams[s.type] = { data: s.data };
      }
    }
  }

  // 6. Anti-cheat — unified pipeline from _shared/anti_cheat.ts
  const latlng = streams.latlng?.data as number[][] | undefined;
  const time = streams.time?.data as number[] | undefined;
  const velocity = streams.velocity_smooth?.data as number[] | undefined;
  const cadence = streams.cadence?.data as number[] | undefined;

  const antiCheatInput = normalizeStravaActivity(activity, {
    latlng: latlng ?? undefined,
    time: time ?? undefined,
    velocity: velocity ?? undefined,
    cadence: cadence ?? undefined,
  });
  // L21-01/02: load profile-aware thresholds for the connected athlete.
  const antiCheatThresholds = await loadAntiCheatThresholds(db, conn.user_id);
  const antiCheatResult = runAntiCheatPipeline(antiCheatInput, antiCheatThresholds);
  const uniqueFlags = antiCheatResult.flags;
  const hasCritical = antiCheatResult.has_critical;

  // 7. Calculate metrics
  const startTimeMs = new Date(activity.start_date).getTime();
  const endTimeMs = startTimeMs + (activity.elapsed_time * 1000);
  const avgPaceSecKm = activity.distance > 0
    ? (activity.moving_time / (activity.distance / 1000))
    : null;

  // 8. Store GPS + create session
  let pointsPath: string | null = null;
  const sessionId = crypto.randomUUID();

  if (latlng && time && latlng.length > 0) {
    const points = latlng.map((ll, i) => {
      const m: Record<string, number> = {
        lat: ll[0], lng: ll[1],
        timestampMs: startTimeMs + (time[i] * 1000),
      };
      if (streams.altitude?.data?.[i] != null) m.alt = streams.altitude.data[i];
      if (velocity?.[i] != null) m.speed = velocity[i];
      return m;
    });
    pointsPath = `${conn.user_id}/${sessionId}.json`;
    const { error: storageErr } = await db.storage
      .from("session-points")
      .upload(pointsPath, JSON.stringify(points), { contentType: "application/json", upsert: true });
    if (storageErr) pointsPath = null;
  }

  const { error: insertErr } = await db.from("sessions").insert({
    id: sessionId,
    user_id: conn.user_id,
    status: 3,
    start_time_ms: startTimeMs,
    end_time_ms: endTimeMs,
    total_distance_m: activity.distance ?? 0,
    moving_ms: (activity.moving_time ?? 0) * 1000,
    avg_pace_sec_km: avgPaceSecKm,
    avg_bpm: activity.average_heartrate ? Math.round(activity.average_heartrate) : null,
    max_bpm: activity.max_heartrate ? Math.round(activity.max_heartrate) : null,
    is_verified: !hasCritical && !!(latlng && latlng.length > 0),
    integrity_flags: uniqueFlags,
    points_path: pointsPath,
    is_synced: true,
    source: "strava",
    strava_activity_id: stravaActivityId,
    device_name: activity.device_name ?? null,
  });

  if (insertErr) {
    const msg = insertErr.message ?? "";
    if (msg.includes("duplicate") || msg.includes("unique")) {
      return { imported: false, ignored: true, reason: "duplicate_insert" };
    }
    throw new Error(`INSERT_FAILED: ${msg}`);
  }

  // Upsert strava_activity_history so polyline fallback works
  const startLatlng = activity.start_latlng as number[] | undefined;
  await db.from("strava_activity_history").upsert({
    user_id: conn.user_id,
    strava_activity_id: stravaActivityId,
    name: activity.name ?? null,
    distance_m: activity.distance ?? 0,
    moving_time_s: activity.moving_time ?? 0,
    elapsed_time_s: activity.elapsed_time ?? 0,
    average_speed: activity.average_speed ?? null,
    max_speed: activity.max_speed ?? null,
    average_heartrate: activity.average_heartrate ?? null,
    max_heartrate: activity.max_heartrate ?? null,
    start_date: activity.start_date ?? null,
    summary_polyline: activity.map?.summary_polyline ?? null,
    activity_type: activity.type ?? null,
    start_lat: startLatlng?.[0] ?? null,
    start_lng: startLatlng?.[1] ?? null,
    imported_at: new Date().toISOString(),
  }, { onConflict: "user_id,strava_activity_id" }).then(() => {}, () => {});

  if (!hasCritical && latlng && latlng.length > 0) {
    try { await linkSessionToChallenges(db, conn.user_id, sessionId, activity); } catch { /* best-effort */ }
    db.rpc("eval_athlete_verification", { p_user_id: conn.user_id }).then(() => {}, () => {});
    db.rpc("recalculate_profile_progress", { p_user_id: conn.user_id }).then(() => {
      db.rpc("evaluate_badges_retroactive", { p_user_id: conn.user_id }).then(() => {}, () => {});
    }, () => {});
  }

  if (latlng && latlng.length > 0) {
    try { await detectAndLinkPark(db, conn.user_id, sessionId, stravaActivityId, activity, latlng); } catch { /* best-effort */ }
  }

  db.from("product_events").insert({
    user_id: conn.user_id,
    event_name: "strava_activity_imported",
    properties: {
      strava_activity_id: stravaActivityId, session_id: sessionId,
      distance_m: activity.distance, moving_time_s: activity.moving_time,
      device_name: activity.device_name, integrity_flags: uniqueFlags,
      is_verified: !hasCritical, source_type: activity.type,
    },
  }).then(() => {}, () => {});

  await logIntegrationEvent(db, {
    provider: "strava",
    event_type: "session_imported",
    status: "success",
    user_id: conn.user_id,
    external_id: String(stravaActivityId),
    metadata: {
      session_id: sessionId,
      activity_type: activity.type,
      distance_m: activity.distance,
      is_verified: !hasCritical,
      integrity_flags: uniqueFlags,
      request_id: requestId,
    },
  });

  return { imported: true, session_id: sessionId };
}

// ── Link session to active challenges ───────────────────────────────────────

async function linkSessionToChallenges(
  db: ReturnType<typeof createClient>,
  userId: string,
  sessionId: string,
  activity: {
    distance: number;
    moving_time: number;
    start_date: string;
    elapsed_time: number;
  },
): Promise<void> {
  const nowMs = Date.now();
  const sessionStartMs = new Date(activity.start_date).getTime();
  const sessionEndMs = sessionStartMs + (activity.elapsed_time * 1000);
  const distanceM = activity.distance ?? 0;
  const movingMs = (activity.moving_time ?? 0) * 1000;
  const avgPaceSecKm = distanceM > 0 ? (activity.moving_time / (distanceM / 1000)) : 0;

  const { data: participations } = await db
    .from("challenge_participants")
    .select("challenge_id, progress_value, contributing_session_ids, status")
    .eq("user_id", userId)
    .eq("status", "accepted");

  if (!participations || participations.length === 0) return;

  const challengeIds = participations.map((p: any) => p.challenge_id);
  const { data: challenges } = await db
    .from("challenges")
    .select("id, status, metric, target, min_session_distance_m, starts_at_ms, ends_at_ms")
    .in("id", challengeIds)
    .eq("status", "active");

  if (!challenges || challenges.length === 0) return;

  for (const ch of challenges) {
    const part = participations.find((p: any) => p.challenge_id === ch.id);
    if (!part) continue;
    if (part.contributing_session_ids?.includes(sessionId)) continue;

    const minDist = ch.min_session_distance_m ?? 0;
    if (distanceM < minDist) continue;

    // For time/pace challenges, athlete must complete the full target distance
    const requiresTarget = ch.metric === "time" || ch.metric === "pace";
    const chTarget = (ch.target as number) ?? 0;
    if (requiresTarget && chTarget > 0 && distanceM < chTarget) continue;

    if (ch.starts_at_ms && ch.ends_at_ms) {
      if (sessionEndMs < ch.starts_at_ms || sessionStartMs > ch.ends_at_ms) continue;
    }

    let metricValue: number;
    switch (ch.metric) {
      case "distance": metricValue = distanceM; break;
      case "pace": metricValue = avgPaceSecKm; break;
      case "time":
        metricValue = (chTarget > 0 && distanceM > chTarget)
          ? movingMs * (chTarget / distanceM)
          : movingMs;
        break;
      default: metricValue = distanceM;
    }

    let newProgress: number;
    if (ch.metric === "pace") {
      newProgress = part.progress_value === 0
        ? metricValue
        : Math.min(metricValue, part.progress_value);
    } else {
      newProgress = (part.progress_value ?? 0) + metricValue;
    }

    const newSessions = [...(part.contributing_session_ids ?? []), sessionId];

    await db
      .from("challenge_participants")
      .update({
        progress_value: newProgress,
        contributing_session_ids: newSessions,
        last_submitted_at_ms: nowMs,
        updated_at: new Date().toISOString(),
      })
      .eq("challenge_id", ch.id)
      .eq("user_id", userId);
  }
}

// ── Park detection ──────────────────────────────────────────────────────────

async function detectAndLinkPark(
  db: ReturnType<typeof createClient>,
  userId: string,
  sessionId: string,
  stravaActivityId: number,
  activity: { distance: number; moving_time: number; start_date: string; average_heartrate?: number },
  latlng: number[][],
): Promise<void> {
  const startLat = latlng[0][0];
  const startLng = latlng[0][1];

  const BBOX_DELTA = 0.1; // ~11 km bounding box
  const { data: parks } = await db
    .from("parks")
    .select("id, center_lat, center_lng, radius_m")
    .gte("center_lat", startLat - BBOX_DELTA)
    .lte("center_lat", startLat + BBOX_DELTA)
    .gte("center_lng", startLng - BBOX_DELTA)
    .lte("center_lng", startLng + BBOX_DELTA);

  if (!parks || parks.length === 0) return;

  for (const park of parks) {
    const dist = haversine(startLat, startLng, park.center_lat, park.center_lng);
    if (dist <= park.radius_m) {
      const { data: profile } = await db
        .from("profiles")
        .select("display_name")
        .eq("id", userId)
        .maybeSingle();

      const avgPace = activity.distance > 0
        ? activity.moving_time / (activity.distance / 1000)
        : null;

      await db.from("park_activities").upsert({
        park_id: park.id,
        user_id: userId,
        session_id: sessionId,
        strava_activity_id: stravaActivityId,
        display_name: profile?.display_name ?? null,
        distance_m: activity.distance ?? 0,
        moving_time_s: activity.moving_time ?? 0,
        avg_pace_sec_km: avgPace,
        avg_heartrate: activity.average_heartrate ?? null,
        start_time: activity.start_date,
      }, { onConflict: "session_id,park_id", ignoreDuplicates: true });

      break; // One park per activity
    }
  }
}

// haversine() is imported from _shared/anti_cheat.ts
