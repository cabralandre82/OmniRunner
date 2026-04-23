/**
 * L07-03 — Retry + alert policy helpers (pure).
 *
 * The retry schedule is exponential backoff capped at
 * `maxDelayMs` with an additive jitter in
 * `[-delay*jitter, +delay*jitter]`. This spreads burst
 * reconnections across a neighbourhood of athletes returning
 * from a trail camp rather than hammering the API the moment
 * the first device sees 4G.
 */

import {
  type OfflineAlert,
  type OfflineAlertPolicy,
  type RetryPolicy,
  DEFAULT_OFFLINE_ALERT_POLICY,
} from "./types";
import type { QueueSnapshot } from "./queue";

export interface NextAttemptInput {
  attempts: number;
  now: number;
  policy: RetryPolicy;
  random?: () => number;
}

export function computeNextAttemptAt(input: NextAttemptInput): number {
  const { attempts, now, policy } = input;
  const random = input.random ?? Math.random;
  const exponent = Math.max(0, attempts - 1);
  const uncapped = policy.baseDelayMs * Math.pow(2, exponent);
  const capped = Math.min(uncapped, policy.maxDelayMs);
  const jitterBand = capped * policy.jitterRatio;
  const jitter = (random() * 2 - 1) * jitterBand;
  const withJitter = Math.max(capped + jitter, 0);
  return Math.floor(now + withJitter);
}

export function evaluateAlert(
  snapshot: QueueSnapshot,
  policy: OfflineAlertPolicy = DEFAULT_OFFLINE_ALERT_POLICY,
): OfflineAlert {
  const pendingTripped = snapshot.pending >= policy.pendingCountThreshold;
  const ageTripped = snapshot.oldestPendingAgeMs >= policy.oldestPendingAgeMsThreshold;
  const deadLetterPresent = snapshot.deadLetter > 0;

  let code: OfflineAlert["code"];
  let severity: OfflineAlert["severity"];

  if (deadLetterPresent) {
    severity = "critical";
    code = "DEAD_LETTERS_PRESENT";
  } else if (pendingTripped && ageTripped) {
    severity = "critical";
    code = "BOTH";
  } else if (ageTripped) {
    severity = "warning";
    code = "AGE_THRESHOLD";
  } else if (pendingTripped) {
    severity = "warning";
    code = "PENDING_THRESHOLD";
  } else {
    severity = "info";
    code = "OK";
  }

  return {
    severity,
    pendingCount: snapshot.pending,
    deadLetterCount: snapshot.deadLetter,
    oldestPendingAgeMs: snapshot.oldestPendingAgeMs,
    code,
  };
}
