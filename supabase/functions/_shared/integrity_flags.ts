/**
 * Official Integrity Flags Dictionary — Omni Runner MVP
 *
 * Single source of truth for all integrity flag codes.
 * Server (verify-session) emits these; client (InvalidatedRunCard) maps them.
 *
 * TWO categories:
 *   CRITICAL — directly impact trust_score and verification state machine.
 *              >= 3 critical-flagged sessions in 30 days → DOWNGRADED.
 *   QUALITY  — informational. Trigger is_verified=false but lower weight.
 *
 * VEHICLE_SUSPECTED is currently client-only (server doesn't receive step
 * cadence data). Included here for completeness and future server-side check.
 */

// ── CRITICAL FLAGS ────────────────────────────────────────────────────────
export const SPEED_IMPOSSIBLE = "SPEED_IMPOSSIBLE";
export const GPS_JUMP = "GPS_JUMP";
export const TELEPORT = "TELEPORT";
export const VEHICLE_SUSPECTED = "VEHICLE_SUSPECTED";
export const NO_MOTION_PATTERN = "NO_MOTION_PATTERN";
export const BACKGROUND_GPS_GAP = "BACKGROUND_GPS_GAP";
export const TIME_SKEW = "TIME_SKEW";

export const CRITICAL_FLAGS: readonly string[] = [
  SPEED_IMPOSSIBLE,
  GPS_JUMP,
  TELEPORT,
  VEHICLE_SUSPECTED,
  NO_MOTION_PATTERN,
  BACKGROUND_GPS_GAP,
  TIME_SKEW,
];

// ── QUALITY FLAGS ─────────────────────────────────────────────────────────
export const TOO_FEW_POINTS = "TOO_FEW_POINTS";
export const TOO_SHORT_DURATION = "TOO_SHORT_DURATION";
export const TOO_SHORT_DISTANCE = "TOO_SHORT_DISTANCE";
export const IMPLAUSIBLE_PACE = "IMPLAUSIBLE_PACE";

export const IMPLAUSIBLE_HR_LOW = "IMPLAUSIBLE_HR_LOW";
export const IMPLAUSIBLE_HR_HIGH = "IMPLAUSIBLE_HR_HIGH";

export const QUALITY_FLAGS: readonly string[] = [
  TOO_FEW_POINTS,
  TOO_SHORT_DURATION,
  TOO_SHORT_DISTANCE,
  IMPLAUSIBLE_PACE,
  IMPLAUSIBLE_HR_LOW,
  IMPLAUSIBLE_HR_HIGH,
];

export const ALL_FLAGS: readonly string[] = [
  ...CRITICAL_FLAGS,
  ...QUALITY_FLAGS,
];

export function isCriticalFlag(flag: string): boolean {
  return CRITICAL_FLAGS.includes(flag);
}
