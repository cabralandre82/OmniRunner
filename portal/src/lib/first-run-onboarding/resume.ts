/**
 * L22-01 — Resume-nudge policy.
 *
 * Determines whether a skipped / stalled onboarding should
 * trigger a re-engagement prompt on the next app open.
 * Pure: accepts the snapshot + "now" as integers and returns
 * a decision. No timers, no notifications.
 */

import { isTerminal } from "./machine";
import { DEFAULT_RESUME_POLICY, type OnboardingSnapshot, type ResumePolicy } from "./types";

export interface ResumeDecision {
  shouldResume: boolean;
  reason:
    | "terminal"
    | "max_resumes_exhausted"
    | "too_recent"
    | "not_stalled"
    | "stalled";
  stalledForMs: number;
  resumeCount: number;
}

export function evaluateResume(
  snapshot: OnboardingSnapshot,
  now: number,
  policy: ResumePolicy = DEFAULT_RESUME_POLICY,
): ResumeDecision {
  const stalledForMs = Math.max(0, now - snapshot.lastUpdatedAt);
  const resumeCount = snapshot.history.filter((entry) => entry.event === "resumed").length;

  if (isTerminal(snapshot)) {
    return { shouldResume: false, reason: "terminal", stalledForMs, resumeCount };
  }
  if (resumeCount >= policy.maxAutoResumes) {
    return { shouldResume: false, reason: "max_resumes_exhausted", stalledForMs, resumeCount };
  }
  const isStalled =
    snapshot.state === "skipped"
      || snapshot.state === "welcome_seen"
      || snapshot.state === "strava_connected"
      || snapshot.state === "zones_configured"
      || snapshot.state === "first_run_planned";
  if (!isStalled) {
    return { shouldResume: false, reason: "not_stalled", stalledForMs, resumeCount };
  }
  if (stalledForMs < policy.autoResumeAfterMs) {
    return { shouldResume: false, reason: "too_recent", stalledForMs, resumeCount };
  }
  return { shouldResume: true, reason: "stalled", stalledForMs, resumeCount };
}
