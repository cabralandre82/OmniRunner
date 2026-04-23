/**
 * L22-01 — First-run onboarding state machine (pure domain).
 *
 * The mobile app no longer captures runs directly; activities
 * come from Strava. So "primeira corrida guiada" isn't "the
 * app walked me through GPS tracking" — it's a guided
 * onboarding checklist that ends with the athlete seeing
 * their first run imported and celebrated.
 *
 * This module owns the state machine only: states, events,
 * valid transitions, progress percentage. No IO, no Date
 * mutation, no localization — the UI consumes it via a thin
 * adapter in Flutter and another in the portal.
 *
 * States (happy path):
 *   not_started
 *     ↓ welcome_shown
 *   welcome_seen
 *     ↓ strava_connect_initiated
 *   strava_connect_in_progress
 *     ↓ strava_connected
 *   strava_connected
 *     ↓ zones_configured  (athlete accepts defaults or edits)
 *   zones_configured
 *     ↓ first_run_planned  (athlete schedules run, or
 *                           imports a past one)
 *   first_run_planned
 *     ↓ first_run_completed
 *   first_run_completed
 *     ↓ celebration_shown
 *   celebrated  (terminal)
 *
 * Opt-out paths:
 *   - skipped from any non-terminal state (athlete clicked
 *     "skip"). Still considered non-terminal because the
 *     nudge engine can resume it.
 *   - dismissed terminal (athlete explicitly told us "stop
 *     showing me this").
 */

export type OnboardingState =
  | "not_started"
  | "welcome_seen"
  | "strava_connect_in_progress"
  | "strava_connected"
  | "zones_configured"
  | "first_run_planned"
  | "first_run_completed"
  | "celebrated"
  | "skipped"
  | "dismissed";

export type OnboardingEvent =
  | { type: "welcome_shown" }
  | { type: "strava_connect_initiated" }
  | { type: "strava_connected" }
  | { type: "strava_connection_failed"; reason: string }
  | { type: "zones_configured" }
  | { type: "first_run_planned" }
  | { type: "first_run_completed" }
  | { type: "celebration_shown" }
  | { type: "skipped" }
  | { type: "dismissed" }
  | { type: "resumed" };

export interface OnboardingSnapshot {
  state: OnboardingState;
  history: ReadonlyArray<OnboardingHistoryEntry>;
  lastUpdatedAt: number;
  startedAt: number;
  celebratedAt?: number;
  skipCount: number;
  lastError?: string;
}

export interface OnboardingHistoryEntry {
  at: number;
  from: OnboardingState;
  to: OnboardingState;
  event: OnboardingEvent["type"];
}

export const TERMINAL_STATES: ReadonlySet<OnboardingState> = new Set([
  "celebrated",
  "dismissed",
]);

/**
 * Progress percentage per state, mapped linearly so the
 * UI can drive a radial progress indicator from a single
 * integer. 0 for not-started, 100 for celebrated. Intermediate
 * values are canonical so the mobile and web charts match
 * without shared code.
 */
export const STATE_PROGRESS: Record<OnboardingState, number> = {
  not_started: 0,
  welcome_seen: 10,
  strava_connect_in_progress: 20,
  strava_connected: 40,
  zones_configured: 55,
  first_run_planned: 70,
  first_run_completed: 90,
  celebrated: 100,
  skipped: 0,
  dismissed: 0,
};

export interface ResumePolicy {
  autoResumeAfterMs: number;
  maxAutoResumes: number;
}

export const DEFAULT_RESUME_POLICY: ResumePolicy = {
  autoResumeAfterMs: 3 * 24 * 60 * 60 * 1000,
  maxAutoResumes: 3,
};
