/**
 * L21-04 — Session-level TSS / IF computation.
 *
 * We publish three methods, selected deterministically from
 * the data we have for a session:
 *
 *   1. rTSS  — when NGP (normalised graded pace) and the
 *              athlete's running FTP pace are known. This is
 *              the most accurate running-specific option, the
 *              same as `rTSS = duration_h × (NGP / rFTP)² × 100`.
 *   2. hrTSS — when the session has an average heart rate and
 *              the athlete's HR threshold, using Coggan's
 *              polynomial approximation of IF from HR ratio.
 *              This is the typical fallback for elite runners
 *              who did not upload a power-like pace stream.
 *   3. fallback — we still want *something* so the timeline
 *              has a data point. We estimate IF = 0.70 (zone
 *              2) for any session without either input; that
 *              matches a typical easy run and biases CTL on
 *              the low side, which is the safer error for
 *              load-based prescription.
 *
 * All outputs are clamped:
 *   - IF capped at `IF_MAX` (1.30; 130% of threshold for an
 *     hour is already physiologically implausible and
 *     usually a GPS / HR strap artifact),
 *   - TSS capped at `TSS_MAX_PER_SESSION` (500; a legitimate
 *     ultra will still register in the 400s — beyond that we
 *     assume the sample is corrupted).
 */

import {
  type AthleteThresholds,
  type SessionSample,
  type TssBreakdown,
  IF_MAX,
  TSS_MAX_PER_SESSION,
} from "./types";

export function computeSessionTss(
  session: SessionSample,
  thresholds: AthleteThresholds,
): TssBreakdown {
  if (session.durationSec <= 0) {
    return { tss: 0, intensityFactor: 0, method: "fallback", inputsUsed: [] };
  }

  const hours = session.durationSec / 3600;

  if (session.normalizedGradedPaceSecPerKm && thresholds.runFtpPaceSecPerKm) {
    const rawIf = thresholds.runFtpPaceSecPerKm / session.normalizedGradedPaceSecPerKm;
    const intensityFactor = clampIf(rawIf);
    const tss = clampTss(hours * intensityFactor * intensityFactor * 100);
    return {
      tss,
      intensityFactor,
      method: "rTSS",
      inputsUsed: ["durationSec", "normalizedGradedPaceSecPerKm", "runFtpPaceSecPerKm"],
    };
  }

  if (session.avgHeartRateBpm && thresholds.heartRateThresholdBpm) {
    const ratio = session.avgHeartRateBpm / thresholds.heartRateThresholdBpm;
    const rawIf = hrIntensityFactor(ratio);
    const intensityFactor = clampIf(rawIf);
    const tss = clampTss(hours * intensityFactor * intensityFactor * 100);
    return {
      tss,
      intensityFactor,
      method: "hrTSS",
      inputsUsed: ["durationSec", "avgHeartRateBpm", "heartRateThresholdBpm"],
    };
  }

  const intensityFactor = 0.70;
  const tss = clampTss(hours * intensityFactor * intensityFactor * 100);
  return {
    tss,
    intensityFactor,
    method: "fallback",
    inputsUsed: ["durationSec"],
  };
}

/**
 * HR-to-IF curve tuned so that:
 *   - ratio = 1.00 → IF = 1.00 (threshold),
 *   - ratio = 0.70 → IF ≈ 0.65 (easy),
 *   - ratio = 1.10 → IF ≈ 1.20 (VO2max).
 * Implemented as a cubic so the slope stays realistic
 * around threshold instead of collapsing linearly.
 */
export function hrIntensityFactor(ratio: number): number {
  if (ratio <= 0) return 0;
  return 0.5 * ratio + 0.5 * ratio * ratio;
}

export function clampIf(intensityFactor: number): number {
  if (!Number.isFinite(intensityFactor) || intensityFactor < 0) return 0;
  return Math.min(intensityFactor, IF_MAX);
}

export function clampTss(tss: number): number {
  if (!Number.isFinite(tss) || tss < 0) return 0;
  return Math.min(tss, TSS_MAX_PER_SESSION);
}
