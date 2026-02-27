import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

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

    // Only process activity creation events
    if (event.object_type !== "activity" || event.aspect_type !== "create") {
      return jsonOk({ ignored: true, reason: `${event.object_type}.${event.aspect_type}` }, requestId);
    }

    const stravaAthleteId = event.owner_id;
    const stravaActivityId = event.object_id;

    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    // 1. Find user by Strava athlete ID
    const { data: conn } = await db
      .from("strava_connections")
      .select("user_id, access_token, refresh_token, expires_at")
      .eq("strava_athlete_id", stravaAthleteId)
      .maybeSingle();

    if (!conn) {
      return jsonOk({ ignored: true, reason: "no_connection", strava_athlete_id: stravaAthleteId }, requestId);
    }

    // 2. Check for duplicate
    const { data: existing } = await db
      .from("sessions")
      .select("id")
      .eq("user_id", conn.user_id)
      .eq("strava_activity_id", stravaActivityId)
      .maybeSingle();

    if (existing) {
      return jsonOk({ ignored: true, reason: "duplicate", strava_activity_id: stravaActivityId }, requestId);
    }

    // 3. Get valid access token (refresh if expired)
    let accessToken = conn.access_token;
    const now = Math.floor(Date.now() / 1000);

    if (conn.expires_at < now + 300) {
      const clientId = Deno.env.get("STRAVA_CLIENT_ID");
      const clientSecret = Deno.env.get("STRAVA_CLIENT_SECRET");

      if (!clientId || !clientSecret) {
        status = 500;
        errorCode = "STRAVA_CONFIG_MISSING";
        return jsonErr(500, "INTERNAL", "Strava credentials not configured", requestId);
      }

      const refreshRes = await fetch("https://www.strava.com/oauth/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          grant_type: "refresh_token",
          refresh_token: conn.refresh_token,
        }),
      });

      if (!refreshRes.ok) {
        console.error(JSON.stringify({ request_id: requestId, fn: FN, error_code: "TOKEN_REFRESH_FAILED", status: refreshRes.status }));
        return jsonOk({ ignored: true, reason: "token_refresh_failed" }, requestId);
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
    }

    // 4. Fetch activity details
    const activityRes = await fetch(
      `https://www.strava.com/api/v3/activities/${stravaActivityId}`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );

    if (!activityRes.ok) {
      console.error(JSON.stringify({ request_id: requestId, fn: FN, error_code: "ACTIVITY_FETCH_FAILED", status: activityRes.status }));
      return jsonOk({ ignored: true, reason: "activity_fetch_failed" }, requestId);
    }

    const activity = await activityRes.json();

    // Only import runs
    const runTypes = ["Run", "TrailRun", "VirtualRun"];
    if (!runTypes.includes(activity.type)) {
      return jsonOk({ ignored: true, reason: `type_${activity.type}` }, requestId);
    }

    // 5. Fetch GPS + HR streams for anti-cheat
    const streamsRes = await fetch(
      `https://www.strava.com/api/v3/activities/${stravaActivityId}/streams?keys=latlng,time,heartrate,velocity_smooth,altitude,cadence&key_type=time`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );

    let streams: Record<string, { data: number[] | number[][] }> = {};
    if (streamsRes.ok) {
      const raw = await streamsRes.json();
      if (Array.isArray(raw)) {
        for (const s of raw) {
          streams[s.type] = { data: s.data };
        }
      }
    }

    // 6. Run anti-cheat on GPS streams
    const integrityFlags: string[] = [];
    const latlng = streams.latlng?.data as number[][] | undefined;
    const time = streams.time?.data as number[] | undefined;
    const velocity = streams.velocity_smooth?.data as number[] | undefined;
    const cadence = streams.cadence?.data as number[] | undefined;

    // Distance check
    if (activity.distance < 200) {
      integrityFlags.push("TOO_SHORT_DISTANCE");
    }

    // Duration check
    if (activity.moving_time < 60) {
      integrityFlags.push("TOO_SHORT_DURATION");
    }

    // Pace check (faster than 2:30/km = world record territory)
    if (activity.distance > 0 && activity.moving_time > 0) {
      const paceSecKm = (activity.moving_time / (activity.distance / 1000));
      if (paceSecKm < 150) {
        integrityFlags.push("SPEED_IMPOSSIBLE");
      }
      if (paceSecKm < 180 || paceSecKm > 1200) {
        integrityFlags.push("IMPLAUSIBLE_PACE");
      }
    }

    // GPS point analysis
    if (latlng && latlng.length > 0 && time && time.length === latlng.length) {
      if (latlng.length < 10) {
        integrityFlags.push("TOO_FEW_POINTS");
      }

      // Check for GPS jumps and speed between consecutive points
      for (let i = 1; i < latlng.length; i++) {
        const dt = (time[i] - time[i - 1]);
        if (dt <= 0) continue;

        const dist = haversine(
          latlng[i - 1][0], latlng[i - 1][1],
          latlng[i][0], latlng[i][1],
        );

        // > 500m between consecutive points = GPS jump
        if (dist > 500 && dt < 30) {
          integrityFlags.push("GPS_JUMP");
          break;
        }

        // > 2km between points = teleport
        if (dist > 2000 && dt < 60) {
          integrityFlags.push("TELEPORT");
          break;
        }

        // Speed > 12 m/s (43 km/h) sustained = vehicle
        const speed = dist / dt;
        if (speed > 12 && dt > 10) {
          integrityFlags.push("SPEED_IMPOSSIBLE");
          break;
        }
      }

      // Check for GPS gaps (> 60s between points)
      let gapCount = 0;
      for (let i = 1; i < time.length; i++) {
        if (time[i] - time[i - 1] > 60) gapCount++;
      }
      if (gapCount > 3) {
        integrityFlags.push("BACKGROUND_GPS_GAP");
      }

      // No motion pattern: velocity too constant (low stddev)
      if (velocity && velocity.length > 20) {
        const nonZero = velocity.filter((v) => v > 0.5);
        if (nonZero.length > 10) {
          const mean = nonZero.reduce((a, b) => a + b, 0) / nonZero.length;
          const variance = nonZero.reduce((a, b) => a + (b - mean) ** 2, 0) / nonZero.length;
          const stddev = Math.sqrt(variance);
          const cv = stddev / mean;
          if (cv < 0.03) {
            integrityFlags.push("NO_MOTION_PATTERN");
          }
        }
      }

      // Vehicle suspected: cadence zero with high speed
      if (cadence && velocity) {
        let zeroCadenceHighSpeed = 0;
        for (let i = 0; i < Math.min(cadence.length, velocity.length); i++) {
          if (cadence[i] === 0 && velocity[i] > 5) zeroCadenceHighSpeed++;
        }
        if (zeroCadenceHighSpeed > cadence.length * 0.5) {
          integrityFlags.push("VEHICLE_SUSPECTED");
        }
      }
    } else if (!latlng || latlng.length === 0) {
      integrityFlags.push("TOO_FEW_POINTS");
    }

    // Deduplicate flags
    const uniqueFlags = [...new Set(integrityFlags)];
    const hasCritical = uniqueFlags.some((f) =>
      ["SPEED_IMPOSSIBLE", "GPS_JUMP", "TELEPORT", "VEHICLE_SUSPECTED",
       "NO_MOTION_PATTERN", "BACKGROUND_GPS_GAP", "TIME_SKEW"].includes(f)
    );

    // 7. Calculate metrics
    const startTimeMs = new Date(activity.start_date).getTime();
    const endTimeMs = startTimeMs + (activity.elapsed_time * 1000);
    const avgPaceSecKm = activity.distance > 0
      ? (activity.moving_time / (activity.distance / 1000))
      : null;

    // 8. Store GPS points in Supabase Storage
    let pointsPath: string | null = null;
    if (latlng && time && latlng.length > 0) {
      const points = latlng.map((ll, i) => ({
        lat: ll[0],
        lng: ll[1],
        ts: startTimeMs + (time[i] * 1000),
        alt: streams.altitude?.data?.[i] ?? null,
        hr: streams.heartrate?.data?.[i] ?? null,
        spd: velocity?.[i] ?? null,
      }));

      const sessionId = crypto.randomUUID();
      pointsPath = `session-points/${conn.user_id}/${sessionId}.json`;

      const { error: storageErr } = await db.storage
        .from("session-points")
        .upload(pointsPath, JSON.stringify(points), {
          contentType: "application/json",
          upsert: true,
        });

      if (storageErr) {
        console.error(JSON.stringify({ request_id: requestId, fn: FN, error_code: "STORAGE_FAILED", detail: storageErr.message }));
        pointsPath = null;
      }

      // 9. Create session
      const { error: insertErr } = await db
        .from("sessions")
        .insert({
          id: sessionId,
          user_id: conn.user_id,
          status: 2, // completed
          start_time_ms: startTimeMs,
          end_time_ms: endTimeMs,
          total_distance_m: activity.distance ?? 0,
          moving_ms: (activity.moving_time ?? 0) * 1000,
          avg_pace_sec_km: avgPaceSecKm,
          avg_bpm: activity.average_heartrate ? Math.round(activity.average_heartrate) : null,
          max_bpm: activity.max_heartrate ? Math.round(activity.max_heartrate) : null,
          is_verified: !hasCritical,
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
          return jsonOk({ ignored: true, reason: "duplicate_insert" }, requestId);
        }
        console.error(JSON.stringify({ request_id: requestId, fn: FN, error_code: "INSERT_FAILED", detail: msg }));
        status = 500;
        errorCode = "INSERT_FAILED";
        return jsonErr(500, "INTERNAL", "Failed to create session", requestId);
      }

      // 10. Link to active challenges (server-side dispatch)
      if (!hasCritical) {
        try {
          await linkSessionToChallenges(db, conn.user_id, sessionId, activity);
        } catch (e) {
          console.error(JSON.stringify({
            request_id: requestId, fn: FN,
            error_code: "CHALLENGE_LINK_FAILED",
            detail: (e as Error).message,
          }));
        }

        db.rpc("eval_athlete_verification", { p_user_id: conn.user_id }).then(() => {}, () => {});
      }

      // 11. Park detection — match GPS start to known parks
      if (latlng && latlng.length > 0) {
        try {
          await detectAndLinkPark(db, conn.user_id, sessionId, stravaActivityId, activity, latlng);
        } catch (e) {
          console.error(JSON.stringify({
            request_id: requestId, fn: FN,
            error_code: "PARK_DETECTION_FAILED",
            detail: (e as Error).message,
          }));
        }
      }

      // 12. Analytics
      db.from("product_events").insert({
        user_id: conn.user_id,
        event_name: "strava_activity_imported",
        properties: {
          strava_activity_id: stravaActivityId,
          session_id: sessionId,
          distance_m: activity.distance,
          moving_time_s: activity.moving_time,
          device_name: activity.device_name,
          integrity_flags: uniqueFlags,
          is_verified: !hasCritical,
          source_type: activity.type,
        },
      }).then(() => {}, () => {});

      return jsonOk({
        imported: true,
        session_id: sessionId,
        strava_activity_id: stravaActivityId,
        distance_m: activity.distance,
        is_verified: !hasCritical,
        integrity_flags: uniqueFlags,
        device_name: activity.device_name,
      }, requestId);
    }

    // No GPS data at all — still create session but not verified
    const sessionId = crypto.randomUUID();
    uniqueFlags.push("TOO_FEW_POINTS");

    await db.from("sessions").insert({
      id: sessionId,
      user_id: conn.user_id,
      status: 2,
      start_time_ms: startTimeMs,
      end_time_ms: endTimeMs,
      total_distance_m: activity.distance ?? 0,
      moving_ms: (activity.moving_time ?? 0) * 1000,
      avg_pace_sec_km: avgPaceSecKm,
      avg_bpm: activity.average_heartrate ? Math.round(activity.average_heartrate) : null,
      max_bpm: activity.max_heartrate ? Math.round(activity.max_heartrate) : null,
      is_verified: false,
      integrity_flags: uniqueFlags,
      is_synced: true,
      source: "strava",
      strava_activity_id: stravaActivityId,
      device_name: activity.device_name ?? null,
    });

    return jsonOk({
      imported: true,
      session_id: sessionId,
      strava_activity_id: stravaActivityId,
      is_verified: false,
      integrity_flags: uniqueFlags,
      no_gps: true,
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
    .select("id, status, metric, min_session_distance_m, starts_at_ms, ends_at_ms")
    .in("id", challengeIds)
    .eq("status", "active");

  if (!challenges || challenges.length === 0) return;

  for (const ch of challenges) {
    const part = participations.find((p: any) => p.challenge_id === ch.id);
    if (!part) continue;
    if (part.contributing_session_ids?.includes(sessionId)) continue;

    const minDist = ch.min_session_distance_m ?? 0;
    if (distanceM < minDist) continue;

    if (ch.starts_at_ms && ch.ends_at_ms) {
      if (sessionEndMs < ch.starts_at_ms || sessionStartMs > ch.ends_at_ms) continue;
    }

    let metricValue: number;
    switch (ch.metric) {
      case "distance": metricValue = distanceM; break;
      case "pace": metricValue = avgPaceSecKm; break;
      case "time": metricValue = movingMs; break;
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

  const { data: parks } = await db
    .from("parks")
    .select("id, center_lat, center_lng, radius_m");

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

      await db.from("park_activities").insert({
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
      });

      break; // One park per activity
    }
  }
}

// ── Haversine distance (meters) ─────────────────────────────────────────────

function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
