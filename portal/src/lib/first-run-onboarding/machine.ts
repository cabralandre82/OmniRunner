/**
 * L22-01 — Pure-functional reducer for the first-run
 * onboarding state machine.
 *
 * The reducer is total: every (state, event) combination
 * either transitions to a new state or returns the current
 * state unchanged with a diagnostic — we never throw, so
 * the mobile app doesn't crash when the athlete races two
 * taps.
 */

import {
  type OnboardingEvent,
  type OnboardingSnapshot,
  type OnboardingState,
  STATE_PROGRESS,
  TERMINAL_STATES,
} from "./types";

const TRANSITIONS: Record<OnboardingState, Partial<Record<OnboardingEvent["type"], OnboardingState>>> = {
  not_started: {
    welcome_shown: "welcome_seen",
    dismissed: "dismissed",
    skipped: "skipped",
  },
  welcome_seen: {
    strava_connect_initiated: "strava_connect_in_progress",
    dismissed: "dismissed",
    skipped: "skipped",
    welcome_shown: "welcome_seen",
  },
  strava_connect_in_progress: {
    strava_connected: "strava_connected",
    strava_connection_failed: "welcome_seen",
    dismissed: "dismissed",
    skipped: "skipped",
  },
  strava_connected: {
    zones_configured: "zones_configured",
    dismissed: "dismissed",
    skipped: "skipped",
  },
  zones_configured: {
    first_run_planned: "first_run_planned",
    dismissed: "dismissed",
    skipped: "skipped",
  },
  first_run_planned: {
    first_run_completed: "first_run_completed",
    dismissed: "dismissed",
    skipped: "skipped",
  },
  first_run_completed: {
    celebration_shown: "celebrated",
    dismissed: "dismissed",
  },
  celebrated: {},
  skipped: {
    resumed: "welcome_seen",
    dismissed: "dismissed",
  },
  dismissed: {},
};

export function initialSnapshot(now: number): OnboardingSnapshot {
  return {
    state: "not_started",
    history: [],
    lastUpdatedAt: now,
    startedAt: now,
    skipCount: 0,
  };
}

export function reduce(
  snapshot: OnboardingSnapshot,
  event: OnboardingEvent,
  now: number,
): OnboardingSnapshot {
  const currentTransitions = TRANSITIONS[snapshot.state] ?? {};
  const next = currentTransitions[event.type];
  if (!next) {
    return snapshot;
  }
  if (next === snapshot.state && event.type === "welcome_shown") {
    return {
      ...snapshot,
      lastUpdatedAt: now,
    };
  }
  const history = [
    ...snapshot.history,
    { at: now, from: snapshot.state, to: next, event: event.type },
  ];
  const celebratedAt = next === "celebrated"
    ? snapshot.celebratedAt ?? now
    : snapshot.celebratedAt;
  const skipCount = event.type === "skipped"
    ? snapshot.skipCount + 1
    : snapshot.skipCount;
  const lastError = event.type === "strava_connection_failed"
    ? event.reason
    : event.type === "resumed" || event.type === "strava_connect_initiated"
      ? undefined
      : snapshot.lastError;
  return {
    ...snapshot,
    state: next,
    history,
    lastUpdatedAt: now,
    celebratedAt,
    skipCount,
    lastError,
  };
}

export function progressPercent(snapshot: OnboardingSnapshot): number {
  return STATE_PROGRESS[snapshot.state] ?? 0;
}

export function isTerminal(snapshot: OnboardingSnapshot): boolean {
  return TERMINAL_STATES.has(snapshot.state);
}

export function canTransition(
  snapshot: OnboardingSnapshot,
  eventType: OnboardingEvent["type"],
): boolean {
  return Boolean(TRANSITIONS[snapshot.state]?.[eventType]);
}

export function nextActionableState(
  snapshot: OnboardingSnapshot,
): OnboardingState | null {
  if (isTerminal(snapshot)) return null;
  if (snapshot.state === "skipped") return "welcome_seen";
  return snapshot.state;
}
