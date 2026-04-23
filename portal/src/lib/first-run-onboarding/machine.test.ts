import { describe, expect, it } from "vitest";
import {
  canTransition,
  initialSnapshot,
  isTerminal,
  nextActionableState,
  progressPercent,
  reduce,
} from "./machine";
import { STATE_PROGRESS } from "./types";

const T0 = Date.UTC(2026, 0, 1);
const T1 = T0 + 60_000;
const T2 = T0 + 120_000;
const T3 = T0 + 180_000;

describe("first-run-onboarding / machine", () => {
  it("starts at not_started with zero progress", () => {
    const s = initialSnapshot(T0);
    expect(s.state).toBe("not_started");
    expect(s.startedAt).toBe(T0);
    expect(s.history).toHaveLength(0);
    expect(progressPercent(s)).toBe(0);
  });

  it("drives the full happy path to celebrated", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T1);
    expect(s.state).toBe("welcome_seen");
    s = reduce(s, { type: "strava_connect_initiated" }, T2);
    expect(s.state).toBe("strava_connect_in_progress");
    s = reduce(s, { type: "strava_connected" }, T3);
    expect(s.state).toBe("strava_connected");
    s = reduce(s, { type: "zones_configured" }, T3 + 10);
    expect(s.state).toBe("zones_configured");
    s = reduce(s, { type: "first_run_planned" }, T3 + 20);
    expect(s.state).toBe("first_run_planned");
    s = reduce(s, { type: "first_run_completed" }, T3 + 30);
    expect(s.state).toBe("first_run_completed");
    s = reduce(s, { type: "celebration_shown" }, T3 + 40);
    expect(s.state).toBe("celebrated");
    expect(s.celebratedAt).toBe(T3 + 40);
    expect(isTerminal(s)).toBe(true);
    expect(progressPercent(s)).toBe(100);
  });

  it("ignores disallowed events without throwing", () => {
    const initial = initialSnapshot(T0);
    const out = reduce(initial, { type: "first_run_completed" }, T1);
    expect(out).toEqual(initial);
    expect(out.history).toHaveLength(0);
  });

  it("failed strava connection rewinds to welcome_seen and stores reason", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T1);
    s = reduce(s, { type: "strava_connect_initiated" }, T2);
    s = reduce(s, {
      type: "strava_connection_failed",
      reason: "auth-cancelled",
    }, T3);
    expect(s.state).toBe("welcome_seen");
    expect(s.lastError).toBe("auth-cancelled");
  });

  it("re-initiating connect clears the stored error", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T1);
    s = reduce(s, { type: "strava_connect_initiated" }, T2);
    s = reduce(s, {
      type: "strava_connection_failed",
      reason: "auth-cancelled",
    }, T3);
    s = reduce(s, { type: "strava_connect_initiated" }, T3 + 10);
    expect(s.state).toBe("strava_connect_in_progress");
    expect(s.lastError).toBeUndefined();
  });

  it("skip increments skipCount and moves to skipped", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T1);
    s = reduce(s, { type: "skipped" }, T2);
    expect(s.state).toBe("skipped");
    expect(s.skipCount).toBe(1);
  });

  it("resume from skipped returns to welcome_seen", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "skipped" }, T1);
    s = reduce(s, { type: "resumed" }, T2);
    expect(s.state).toBe("welcome_seen");
    expect(nextActionableState(s)).toBe("welcome_seen");
  });

  it("dismissed is terminal and absorbs further events", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "dismissed" }, T1);
    expect(s.state).toBe("dismissed");
    expect(isTerminal(s)).toBe(true);
    const ignored = reduce(s, { type: "welcome_shown" }, T2);
    expect(ignored.state).toBe("dismissed");
    expect(ignored.history).toHaveLength(s.history.length);
  });

  it("celebrated absorbs further events", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T1);
    s = reduce(s, { type: "strava_connect_initiated" }, T1);
    s = reduce(s, { type: "strava_connected" }, T1);
    s = reduce(s, { type: "zones_configured" }, T1);
    s = reduce(s, { type: "first_run_planned" }, T1);
    s = reduce(s, { type: "first_run_completed" }, T1);
    s = reduce(s, { type: "celebration_shown" }, T2);
    const after = reduce(s, { type: "welcome_shown" }, T3);
    expect(after).toEqual(s);
  });

  it("canTransition mirrors reducer behaviour", () => {
    const s = initialSnapshot(T0);
    expect(canTransition(s, "welcome_shown")).toBe(true);
    expect(canTransition(s, "celebration_shown")).toBe(false);
  });

  it("progressPercent exposes canonical table for every state", () => {
    for (const state of Object.keys(STATE_PROGRESS)) {
      expect(STATE_PROGRESS[state as keyof typeof STATE_PROGRESS]).toBeGreaterThanOrEqual(0);
      expect(STATE_PROGRESS[state as keyof typeof STATE_PROGRESS]).toBeLessThanOrEqual(100);
    }
  });

  it("history preserves ordering and event metadata", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T1);
    s = reduce(s, { type: "strava_connect_initiated" }, T2);
    expect(s.history).toEqual([
      { at: T1, from: "not_started", to: "welcome_seen", event: "welcome_shown" },
      { at: T2, from: "welcome_seen", to: "strava_connect_in_progress", event: "strava_connect_initiated" },
    ]);
  });
});
