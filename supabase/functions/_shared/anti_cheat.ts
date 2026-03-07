/**
 * Unified anti-cheat pipeline — single source of truth.
 *
 * Both verify-session (app-reported) and strava-webhook (Strava import)
 * normalize their data into AntiCheatInput and call runAntiCheatPipeline().
 *
 * Thresholds are canonical and shared. Data format differences are
 * handled by the normalizer helpers exported at the bottom.
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

// ── Thresholds ───────────────────────────────────────────────────────────────

const MAX_SPEED_MS = 12.5;            // ~45 km/h
const TELEPORT_SPEED_MS = 50.0;       // ~180 km/h
const GPS_JUMP_THRESHOLD_M = 500;
const MAX_ACCURACY_M = 15.0;
const MIN_POINTS = 5;
const MIN_DURATION_MS = 60_000;        // 1 min
const MAX_PACE_SEC_KM = 90;           // 1:30/km — world record sprint
const MIN_DISTANCE_M = 50;
const GPS_GAP_THRESHOLD_MS = 60_000;   // 60s
const MOTION_RADIUS_M = 150;
const MIN_HR_RUNNING_BPM = 80;
const MAX_HR_BPM = 220;
const HR_CHECK_MIN_DISTANCE_M = 1000;
const VEHICLE_MIN_SPEED_KMH = 15;
const VEHICLE_MAX_CADENCE_SPM = 100;
const VEHICLE_MIN_DISTANCE_M = 1000;
const SPEED_VIOLATION_THRESHOLD = 0.1; // >10% of segments

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

function hasGoodAccuracy(p: AntiCheatPoint): boolean {
  return p.accuracy != null && p.accuracy <= MAX_ACCURACY_M;
}

// ── Pipeline ─────────────────────────────────────────────────────────────────

export function runAntiCheatPipeline(input: AntiCheatInput): AntiCheatResult {
  const flags: string[] = [];
  const { points, total_distance_m, duration_ms, start_time_ms, end_time_ms } = input;

  // ─ Quality checks ──────────────────────────────────────────────────────

  if (points.length < MIN_POINTS) {
    flags.push(TOO_FEW_POINTS);
  }

  if (duration_ms < MIN_DURATION_MS) {
    flags.push(TOO_SHORT_DURATION);
  }

  if (total_distance_m < MIN_DISTANCE_M) {
    flags.push(TOO_SHORT_DISTANCE);
  }

  if (total_distance_m > 0 && duration_ms > 0) {
    const paceSecKm = (duration_ms / 1000) / (total_distance_m / 1000);
    if (paceSecKm < MAX_PACE_SEC_KM && total_distance_m > 1000) {
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

      if (speed > MAX_SPEED_MS) {
        speedViolations++;
      }

      if (dist > GPS_JUMP_THRESHOLD_M) {
        gpsJumps++;
      }

      if (
        hasGoodAccuracy(prev) &&
        hasGoodAccuracy(curr) &&
        speed > TELEPORT_SPEED_MS
      ) {
        teleportViolations++;
      }
    }

    if (speedViolations > totalSegments * SPEED_VIOLATION_THRESHOLD) {
      flags.push(SPEED_IMPOSSIBLE);
    }
    if (gpsJumps > 0) {
      flags.push(GPS_JUMP);
    }
    if (teleportViolations > 0) {
      flags.push(TELEPORT);
    }
    if (maxGapMs > GPS_GAP_THRESHOLD_MS) {
      flags.push(BACKGROUND_GPS_GAP);
    }
  }

  // ─ NO_MOTION_PATTERN ───────────────────────────────────────────────────

  if (points.length >= MIN_POINTS && total_distance_m >= MIN_DISTANCE_M) {
    const cLat = points.reduce((s, pt) => s + pt.lat, 0) / points.length;
    const cLng = points.reduce((s, pt) => s + pt.lng, 0) / points.length;
    let maxDist = 0;
    for (const pt of points) {
      const d = haversine(cLat, cLng, pt.lat, pt.lng);
      if (d > maxDist) maxDist = d;
    }
    if (maxDist < MOTION_RADIUS_M) {
      flags.push(NO_MOTION_PATTERN);
    }
  }

  // ─ HR plausibility ─────────────────────────────────────────────────────

  if (input.avg_bpm != null && input.avg_bpm > 0) {
    if (input.avg_bpm > MAX_HR_BPM) {
      flags.push(IMPLAUSIBLE_HR_HIGH);
    } else if (
      input.avg_bpm < MIN_HR_RUNNING_BPM &&
      total_distance_m >= HR_CHECK_MIN_DISTANCE_M
    ) {
      flags.push(IMPLAUSIBLE_HR_LOW);
    }
  }

  // ─ Cadence vs speed correlation (vehicle detection) ────────────────────

  if (
    input.avg_cadence_spm != null &&
    input.avg_cadence_spm >= 0 &&
    total_distance_m >= VEHICLE_MIN_DISTANCE_M &&
    duration_ms > 0
  ) {
    const avgSpeedKmh = (total_distance_m / 1000) / (duration_ms / 3_600_000);
    if (avgSpeedKmh > VEHICLE_MIN_SPEED_KMH && input.avg_cadence_spm < VEHICLE_MAX_CADENCE_SPM) {
      flags.push(VEHICLE_SUSPECTED);
    }
  }

  // Per-point cadence vs speed (Strava-style, when individual cadence data available)
  if (!flags.includes(VEHICLE_SUSPECTED) && total_distance_m >= VEHICLE_MIN_DISTANCE_M) {
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
