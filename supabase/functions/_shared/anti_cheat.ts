/**
 * Unified anti-cheat pipeline — single source of truth.
 *
 * Both verify-session (app-reported) and strava-webhook (Strava import)
 * normalize their data into AntiCheatInput and call runAntiCheatPipeline().
 *
 * Thresholds were hard-coded constants until L21-01/L21-02 (2026-04-21):
 *   - L21-01: MAX_SPEED_MS = 12.5 m/s flagged Usain-Bolt-class sprinters
 *             (peak ~12.27 m/s) as SPEED_IMPOSSIBLE. Elite athletes
 *             could not use the product.
 *   - L21-02: MAX_HR_BPM = 220 ignored measured-max-HR data; young
 *             athletes in VO2max often hit 210-225 BPM on chest-strap
 *             data (Tanaka 2001).
 *
 * Fix: thresholds are now a value of type `AntiCheatThresholds` derived
 *      from the user's skill bracket, age and measured max HR via the
 *      SQL RPC `fn_get_anti_cheat_thresholds(user_id)`. The TS helper
 *      `getThresholdsForBracket()` mirrors the SQL ladder 1:1 for unit
 *      tests and offline scenarios.
 *
 * Backwards compat: callers that don't pass thresholds still get the
 *      pre-fix behaviour via `DEFAULT_ANTI_CHEAT_THRESHOLDS`.
 *
 * Data format differences are handled by the normalizer helpers
 * exported at the bottom.
 */

import {
  SPEED_IMPOSSIBLE,
  GPS_JUMP,
  TELEPORT,
  VEHICLE_SUSPECTED,
  NO_MOTION_PATTERN,
  BACKGROUND_GPS_GAP,
  TIME_SKEW,
  TOO_FEW_POINTS,
  TOO_SHORT_DURATION,
  TOO_SHORT_DISTANCE,
  IMPLAUSIBLE_PACE,
  IMPLAUSIBLE_HR_LOW,
  IMPLAUSIBLE_HR_HIGH,
  CRITICAL_FLAGS,
} from "./integrity_flags.ts";

// ── Data contract ────────────────────────────────────────────────────────────

export interface AntiCheatPoint {
  lat: number;
  lng: number;
  timestamp_ms: number;
  accuracy?: number;
  speed?: number;
  cadence?: number;
}

export interface AntiCheatInput {
  points: AntiCheatPoint[];
  total_distance_m: number;
  duration_ms: number;
  start_time_ms: number;
  end_time_ms: number;
  avg_bpm?: number;
  avg_cadence_spm?: number;
}

export interface AntiCheatResult {
  flags: string[];
  is_verified: boolean;
  has_critical: boolean;
}

/**
 * L21-01 + L21-02: per-user threshold bag. Mirrored 1:1 by the SQL
 * function `fn_get_anti_cheat_thresholds(user_id)`. Edge Functions
 * call the RPC once per request and pass the result here.
 *
 * `source` is purely informational (Sentry tag for forensics).
 */
export interface AntiCheatThresholds {
  max_speed_ms: number;
  teleport_speed_ms: number;
  gps_jump_threshold_m: number;
  max_accuracy_m: number;
  min_points: number;
  min_duration_ms: number;
  max_pace_sec_km: number;
  min_distance_m: number;
  gps_gap_threshold_ms: number;
  motion_radius_m: number;
  min_hr_running_bpm: number;
  max_hr_bpm: number;
  hr_check_min_distance_m: number;
  vehicle_min_speed_kmh: number;
  vehicle_max_cadence_spm: number;
  vehicle_min_distance_m: number;
  speed_violation_threshold: number;
  source?: string;
}

/**
 * Pre-L21 hard-coded constants. Preserved as the default so that
 * legacy callers passing no thresholds keep their exact behaviour.
 */
export const DEFAULT_ANTI_CHEAT_THRESHOLDS: AntiCheatThresholds = {
  max_speed_ms: 12.5,             // ~45 km/h
  teleport_speed_ms: 50.0,        // ~180 km/h
  gps_jump_threshold_m: 500,
  max_accuracy_m: 15.0,
  min_points: 5,
  min_duration_ms: 60_000,        // 1 min
  max_pace_sec_km: 90,            // 1:30/km — world record sprint
  min_distance_m: 50,
  gps_gap_threshold_ms: 60_000,   // 60s
  motion_radius_m: 150,
  min_hr_running_bpm: 80,
  max_hr_bpm: 220,
  hr_check_min_distance_m: 1000,
  vehicle_min_speed_kmh: 15,
  vehicle_max_cadence_spm: 100,
  vehicle_min_distance_m: 1000,
  speed_violation_threshold: 0.1, // > 10 % of segments
  source: "default",
};

/**
 * L21-01 + L21-02: derive thresholds from a skill bracket + optional
 * profile signals. MUST stay in lock-step with the SQL function
 * `public.fn_get_anti_cheat_thresholds`. The unit test
 * `anti_cheat.test.ts` and the PG runner
 * `tools/test_l21_01_02_anti_cheat_profile.ts` cross-check parity.
 *
 * Threshold ladder (mirrors SQL):
 *
 *   bracket       | max_speed | teleport | min_hr | max_hr (default)
 *   beginner      | 12.5  m/s | 50 m/s   | 80     | 220
 *   intermediate  | 12.5  m/s | 50 m/s   | 75     | 220
 *   advanced      | 13.5  m/s | 55 m/s   | 70     | 225
 *   elite         | 15.0  m/s | 60 m/s   | 60     | 230
 *
 * Then `max_hr` is widened (never narrowed) by:
 *   • measured_max_hr_bpm (+5 BPM headroom) IF measurement <= 6 months old
 *   • Tanaka floor (225 - age)             IF birth_date set
 * And finally clamped to [185, 250].
 */
export function getThresholdsForBracket(
  bracket: string | null | undefined,
  options?: {
    measuredMaxHrBpm?: number;
    measuredMaxHrAt?: Date;
    ageYears?: number;
    now?: Date;
  },
): AntiCheatThresholds {
  const sourceParts: string[] = [];

  let effective = (bracket ?? "").toLowerCase();
  if (
    effective !== "beginner" &&
    effective !== "intermediate" &&
    effective !== "advanced" &&
    effective !== "elite"
  ) {
    sourceParts.push("default");
    effective = "beginner";
  } else {
    sourceParts.push("computed");
  }

  let maxSpeed = 12.5;
  let teleport = 50.0;
  let minHr = 80;
  let maxHr = 220;

  switch (effective) {
    case "elite":
      maxSpeed = 15.0;
      teleport = 60.0;
      minHr = 60;
      maxHr = 230;
      break;
    case "advanced":
      maxSpeed = 13.5;
      teleport = 55.0;
      minHr = 70;
      maxHr = 225;
      break;
    case "intermediate":
      maxSpeed = 12.5;
      teleport = 50.0;
      minHr = 75;
      maxHr = 220;
      break;
    default: // beginner
      maxSpeed = 12.5;
      teleport = 50.0;
      minHr = 80;
      maxHr = 220;
      break;
  }

  // Tanaka floor: 225 - age. Only widens, never narrows.
  if (
    options?.ageYears != null &&
    options.ageYears >= 10 &&
    options.ageYears <= 90
  ) {
    const tanakaFloor = 225 - options.ageYears;
    if (tanakaFloor > maxHr) {
      maxHr = tanakaFloor;
      sourceParts.push(`tanaka_floor=${tanakaFloor}`);
    }
  }

  // Measured-HR floor: only counts if measurement is at most 6 months old.
  if (
    options?.measuredMaxHrBpm != null &&
    options.measuredMaxHrBpm > 0 &&
    options.measuredMaxHrAt instanceof Date
  ) {
    const now = options.now ?? new Date();
    const sixMonthsMs = 1000 * 60 * 60 * 24 * 30 * 6;
    const ageMs = now.getTime() - options.measuredMaxHrAt.getTime();
    if (ageMs >= 0 && ageMs <= sixMonthsMs) {
      const measuredFloor = options.measuredMaxHrBpm + 5;
      if (measuredFloor > maxHr) {
        maxHr = measuredFloor;
        sourceParts.push(`measured_max_hr=${options.measuredMaxHrBpm}`);
      }
    }
  }

  // Final clamp [185, 250].
  if (maxHr > 250) maxHr = 250;
  if (maxHr < 185) maxHr = 185;

  return {
    ...DEFAULT_ANTI_CHEAT_THRESHOLDS,
    max_speed_ms: maxSpeed,
    teleport_speed_ms: teleport,
    min_hr_running_bpm: minHr,
    max_hr_bpm: maxHr,
    source: sourceParts.join(","),
  };
}

// ── Geo helper ───────────────────────────────────────────────────────────────

export function haversine(
  lat1: number, lon1: number,
  lat2: number, lon2: number,
): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function hasGoodAccuracy(p: AntiCheatPoint, maxAccuracyM: number): boolean {
  return p.accuracy != null && p.accuracy <= maxAccuracyM;
}

// ── Pipeline ─────────────────────────────────────────────────────────────────

/**
 * Run the unified anti-cheat pipeline.
 *
 * @param input       normalized session payload (see normalizers)
 * @param thresholds  per-user thresholds. Omitting falls back to
 *                    {@link DEFAULT_ANTI_CHEAT_THRESHOLDS}, which
 *                    preserves pre-L21-01/02 behaviour for legacy
 *                    callers and tests.
 */
export function runAntiCheatPipeline(
  input: AntiCheatInput,
  thresholds: AntiCheatThresholds = DEFAULT_ANTI_CHEAT_THRESHOLDS,
): AntiCheatResult {
  const T = thresholds;
  const flags: string[] = [];
  const { points, total_distance_m, duration_ms, start_time_ms, end_time_ms } = input;

  // ─ Quality checks ──────────────────────────────────────────────────────

  if (points.length < T.min_points) {
    flags.push(TOO_FEW_POINTS);
  }

  if (duration_ms < T.min_duration_ms) {
    flags.push(TOO_SHORT_DURATION);
  }

  if (total_distance_m < T.min_distance_m) {
    flags.push(TOO_SHORT_DISTANCE);
  }

  if (total_distance_m > 0 && duration_ms > 0) {
    const paceSecKm = (duration_ms / 1000) / (total_distance_m / 1000);
    if (paceSecKm < T.max_pace_sec_km && total_distance_m > 1000) {
      flags.push(IMPLAUSIBLE_PACE);
    }
  }

  // ─ TIME_SKEW ───────────────────────────────────────────────────────────

  if (end_time_ms <= start_time_ms) {
    flags.push(TIME_SKEW);
  } else if (points.length >= 2) {
    let negativeDeltas = 0;
    for (let i = 1; i < points.length; i++) {
      if (points[i].timestamp_ms < points[i - 1].timestamp_ms) {
        negativeDeltas++;
      }
    }
    if (negativeDeltas > points.length * 0.1) {
      flags.push(TIME_SKEW);
    }
  }

  // ─ Route-based checks (need >= 2 points) ───────────────────────────────

  if (points.length >= 2) {
    let speedViolations = 0;
    let gpsJumps = 0;
    let teleportViolations = 0;
    let maxGapMs = 0;
    const totalSegments = points.length - 1;

    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      const dtMs = curr.timestamp_ms - prev.timestamp_ms;
      const dt = dtMs / 1000;

      if (dtMs > maxGapMs) maxGapMs = dtMs;
      if (dt <= 0) continue;

      const dist = haversine(prev.lat, prev.lng, curr.lat, curr.lng);
      const speed = dist / dt;

      if (speed > T.max_speed_ms) {
        speedViolations++;
      }

      if (dist > T.gps_jump_threshold_m) {
        gpsJumps++;
      }

      if (
        hasGoodAccuracy(prev, T.max_accuracy_m) &&
        hasGoodAccuracy(curr, T.max_accuracy_m) &&
        speed > T.teleport_speed_ms
      ) {
        teleportViolations++;
      }
    }

    if (speedViolations > totalSegments * T.speed_violation_threshold) {
      flags.push(SPEED_IMPOSSIBLE);
    }
    if (gpsJumps > 0) {
      flags.push(GPS_JUMP);
    }
    if (teleportViolations > 0) {
      flags.push(TELEPORT);
    }
    if (maxGapMs > T.gps_gap_threshold_ms) {
      flags.push(BACKGROUND_GPS_GAP);
    }
  }

  // ─ NO_MOTION_PATTERN ───────────────────────────────────────────────────

  if (points.length >= T.min_points && total_distance_m >= T.min_distance_m) {
    const cLat = points.reduce((s, pt) => s + pt.lat, 0) / points.length;
    const cLng = points.reduce((s, pt) => s + pt.lng, 0) / points.length;
    let maxDist = 0;
    for (const pt of points) {
      const d = haversine(cLat, cLng, pt.lat, pt.lng);
      if (d > maxDist) maxDist = d;
    }
    if (maxDist < T.motion_radius_m) {
      flags.push(NO_MOTION_PATTERN);
    }
  }

  // ─ HR plausibility ─────────────────────────────────────────────────────

  if (input.avg_bpm != null && input.avg_bpm > 0) {
    if (input.avg_bpm > T.max_hr_bpm) {
      flags.push(IMPLAUSIBLE_HR_HIGH);
    } else if (
      input.avg_bpm < T.min_hr_running_bpm &&
      total_distance_m >= T.hr_check_min_distance_m
    ) {
      flags.push(IMPLAUSIBLE_HR_LOW);
    }
  }

  // ─ Cadence vs speed correlation (vehicle detection) ────────────────────

  if (
    input.avg_cadence_spm != null &&
    input.avg_cadence_spm >= 0 &&
    total_distance_m >= T.vehicle_min_distance_m &&
    duration_ms > 0
  ) {
    const avgSpeedKmh = (total_distance_m / 1000) / (duration_ms / 3_600_000);
    if (
      avgSpeedKmh > T.vehicle_min_speed_kmh &&
      input.avg_cadence_spm < T.vehicle_max_cadence_spm
    ) {
      flags.push(VEHICLE_SUSPECTED);
    }
  }

  // Per-point cadence vs speed (Strava-style, when individual cadence data available)
  if (!flags.includes(VEHICLE_SUSPECTED) && total_distance_m >= T.vehicle_min_distance_m) {
    const pointsWithCadence = points.filter(p => p.cadence != null && p.speed != null);
    if (pointsWithCadence.length > 20) {
      let zeroCadenceHighSpeed = 0;
      for (const p of pointsWithCadence) {
        if (p.cadence === 0 && (p.speed ?? 0) > 5) zeroCadenceHighSpeed++;
      }
      if (zeroCadenceHighSpeed > pointsWithCadence.length * 0.5) {
        flags.push(VEHICLE_SUSPECTED);
      }
    }
  }

  // ─ Verdict ─────────────────────────────────────────────────────────────

  const uniqueFlags = [...new Set(flags)];
  const hasCritical = uniqueFlags.some(f => CRITICAL_FLAGS.includes(f));

  return {
    flags: uniqueFlags,
    is_verified: uniqueFlags.length === 0,
    has_critical: hasCritical,
  };
}

// ── Normalizers ──────────────────────────────────────────────────────────────

/**
 * Normalize app-reported LocationPoint[] into AntiCheatInput.
 */
export function normalizeAppSession(payload: {
  route: Array<{ lat: number; lng: number; accuracy?: number; speed?: number; timestamp_ms: number }>;
  total_distance_m: number;
  start_time_ms: number;
  end_time_ms: number;
  avg_bpm?: number;
  avg_cadence_spm?: number;
}): AntiCheatInput {
  return {
    points: payload.route.map(p => ({
      lat: p.lat,
      lng: p.lng,
      timestamp_ms: p.timestamp_ms,
      accuracy: p.accuracy,
      speed: p.speed,
    })),
    total_distance_m: payload.total_distance_m,
    duration_ms: payload.end_time_ms - payload.start_time_ms,
    start_time_ms: payload.start_time_ms,
    end_time_ms: payload.end_time_ms,
    avg_bpm: payload.avg_bpm,
    avg_cadence_spm: payload.avg_cadence_spm,
  };
}

/**
 * Normalize Strava activity + streams into AntiCheatInput.
 */
export function normalizeStravaActivity(
  activity: {
    distance: number;
    moving_time: number;
    elapsed_time: number;
    start_date: string;
    average_heartrate?: number;
  },
  streams: {
    latlng?: number[][];
    time?: number[];
    velocity?: number[];
    cadence?: number[];
  },
): AntiCheatInput {
  const startTimeMs = new Date(activity.start_date).getTime();
  const endTimeMs = startTimeMs + (activity.elapsed_time * 1000);
  const durationMs = (activity.moving_time ?? activity.elapsed_time) * 1000;

  const points: AntiCheatPoint[] = [];
  if (streams.latlng && streams.time && streams.latlng.length === streams.time.length) {
    for (let i = 0; i < streams.latlng.length; i++) {
      const ll = streams.latlng[i];
      points.push({
        lat: ll[0],
        lng: ll[1],
        timestamp_ms: startTimeMs + (streams.time[i] * 1000),
        speed: streams.velocity?.[i],
        cadence: streams.cadence?.[i],
      });
    }
  }

  return {
    points,
    total_distance_m: activity.distance ?? 0,
    duration_ms: durationMs,
    start_time_ms: startTimeMs,
    end_time_ms: endTimeMs,
    avg_bpm: activity.average_heartrate
      ? Math.round(activity.average_heartrate)
      : undefined,
  };
}

// ── Threshold loader (Edge Function helper) ──────────────────────────────────

/**
 * Helper for Edge Functions: fetches the per-user thresholds from
 * Postgres via the canonical RPC `fn_get_anti_cheat_thresholds`.
 *
 * Returns DEFAULT_ANTI_CHEAT_THRESHOLDS if the RPC fails for any
 * reason (db unreachable, function missing, malformed row), so the
 * pipeline never blows up at the call site. Callers SHOULD log the
 * fallback through their existing observability so we can spot
 * silent degradation in Sentry.
 *
 * `db` must be a Supabase client with the `.rpc(name, args)` method.
 */
// deno-lint-ignore no-explicit-any
export async function loadAntiCheatThresholds(db: any, userId: string): Promise<AntiCheatThresholds> {
  try {
    const res = await db.rpc("fn_get_anti_cheat_thresholds", { p_user_id: userId });
    const error = res?.error;
    let row = res?.data;
    if (Array.isArray(row)) row = row[0];
    if (error || !row || typeof row !== "object") {
      return DEFAULT_ANTI_CHEAT_THRESHOLDS;
    }

    const num = (v: unknown, fallback: number): number => {
      const n = typeof v === "string" ? Number(v) : (v as number);
      return Number.isFinite(n) ? n : fallback;
    };

    return {
      ...DEFAULT_ANTI_CHEAT_THRESHOLDS,
      max_speed_ms: num(row.max_speed_ms, DEFAULT_ANTI_CHEAT_THRESHOLDS.max_speed_ms),
      teleport_speed_ms: num(row.teleport_speed_ms, DEFAULT_ANTI_CHEAT_THRESHOLDS.teleport_speed_ms),
      min_hr_running_bpm: num(row.min_hr_bpm, DEFAULT_ANTI_CHEAT_THRESHOLDS.min_hr_running_bpm),
      max_hr_bpm: num(row.max_hr_bpm, DEFAULT_ANTI_CHEAT_THRESHOLDS.max_hr_bpm),
      source:
        typeof row.skill_bracket === "string" && typeof row.source === "string"
          ? `${row.skill_bracket}:${row.source}`
          : (typeof row.source === "string" ? row.source : "rpc"),
    };
  } catch (_err) {
    return DEFAULT_ANTI_CHEAT_THRESHOLDS;
  }
}
