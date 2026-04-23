/**
 * L21-04 — Training load value objects (pure domain).
 *
 * Data model for Training Stress Score (TSS), Intensity
 * Factor (IF), Chronic Training Load (CTL), Acute Training
 * Load (ATL) and Training Stress Balance (TSB).
 *
 * Source of truth for running is Strava (the mobile app no
 * longer captures sessions directly), so we normalise on
 * whatever the Strava activity exposes: duration, average
 * heart-rate, elevation-adjusted pace. All computation lives
 * here in TS so the portal dashboards, the coach UI, and
 * future edge aggregators share the same math — no divergence
 * between "what the athlete's CTL looks like on the mobile"
 * and "what the coach sees on the portal".
 *
 * Conventions:
 *   - CTL time constant τ = 42 days (fitness),
 *   - ATL time constant τ =  7 days (fatigue),
 *   - TSB = CTL − ATL, the classical Banister "form" metric.
 *   - A 1-hour effort at threshold (IF = 1.0) yields TSS = 100.
 */

export interface AthleteThresholds {
  heartRateThresholdBpm?: number;
  heartRateMaxBpm?: number;
  runFtpPaceSecPerKm?: number;
}

export interface SessionSample {
  id: string;
  athleteUserId: string;
  startedAt: number;
  durationSec: number;
  movingTimeSec?: number;
  distanceM?: number;
  avgHeartRateBpm?: number;
  normalizedGradedPaceSecPerKm?: number;
  sport?: "run" | "trail_run" | "bike" | "other";
}

export interface TssBreakdown {
  tss: number;
  intensityFactor: number;
  method: "rTSS" | "hrTSS" | "fallback";
  inputsUsed: Array<"durationSec" | "avgHeartRateBpm" | "heartRateThresholdBpm"
    | "normalizedGradedPaceSecPerKm" | "runFtpPaceSecPerKm">;
}

export interface DailyLoad {
  day: string;
  tssSum: number;
  sessionCount: number;
}

export interface LoadPoint {
  day: string;
  ctl: number;
  atl: number;
  tsb: number;
  dailyTss: number;
}

export const CTL_TAU_DAYS = 42;
export const ATL_TAU_DAYS = 7;

export const TSS_MAX_PER_SESSION = 500;
export const IF_MAX = 1.3;

export type TrainingZone =
  | "rest"
  | "optimal"
  | "productive"
  | "overreaching"
  | "high_risk";

export interface TrainingZoneBand {
  zone: TrainingZone;
  tsbMin: number;
  tsbMax: number;
  description: string;
}

export const TRAINING_ZONE_BANDS: ReadonlyArray<TrainingZoneBand> = [
  { zone: "high_risk",   tsbMin: Number.NEGATIVE_INFINITY, tsbMax: -30, description: "deep fatigue — injury or illness risk" },
  { zone: "overreaching", tsbMin: -30, tsbMax: -10, description: "heavy block — controlled overreach" },
  { zone: "productive",  tsbMin: -10, tsbMax:   5, description: "productive training load" },
  { zone: "optimal",     tsbMin:   5, tsbMax:  15, description: "race-ready / peaking" },
  { zone: "rest",        tsbMin:  15, tsbMax: Number.POSITIVE_INFINITY, description: "detraining risk" },
];
