import { describe, expect, it } from "vitest";
import { initialSnapshot, reduce } from "./machine";
import { evaluateResume } from "./resume";
import { DEFAULT_RESUME_POLICY } from "./types";

const T0 = Date.UTC(2026, 0, 1);
const DAY = 86_400_000;

describe("first-run-onboarding / resume", () => {
  it("terminal snapshots never trigger resume", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "dismissed" }, T0);
    const decision = evaluateResume(s, T0 + 10 * DAY);
    expect(decision.shouldResume).toBe(false);
    expect(decision.reason).toBe("terminal");
  });

  it("not-stalled states don't trigger resume", () => {
    const s = initialSnapshot(T0);
    const decision = evaluateResume(s, T0 + 30 * DAY);
    expect(decision.shouldResume).toBe(false);
    expect(decision.reason).toBe("not_stalled");
  });

  it("too-recent stalls don't trigger resume", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T0);
    const decision = evaluateResume(s, T0 + 1 * DAY);
    expect(decision.shouldResume).toBe(false);
    expect(decision.reason).toBe("too_recent");
    expect(decision.stalledForMs).toBe(1 * DAY);
  });

  it("stalled welcome_seen → resume", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "welcome_shown" }, T0);
    const decision = evaluateResume(s, T0 + 4 * DAY);
    expect(decision.shouldResume).toBe(true);
    expect(decision.reason).toBe("stalled");
    expect(decision.stalledForMs).toBe(4 * DAY);
  });

  it("stalled skipped → resume", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "skipped" }, T0);
    const decision = evaluateResume(s, T0 + 5 * DAY);
    expect(decision.shouldResume).toBe(true);
    expect(decision.reason).toBe("stalled");
  });

  it("resume count is capped by policy", () => {
    let s = initialSnapshot(T0);
    s = reduce(s, { type: "skipped" }, T0);
    for (let i = 0; i < DEFAULT_RESUME_POLICY.maxAutoResumes; i += 1) {
      s = reduce(s, { type: "resumed" }, T0 + (i + 1) * 10_000);
      s = reduce(s, { type: "skipped" }, T0 + (i + 1) * 10_000 + 5_000);
    }
    const decision = evaluateResume(s, T0 + 30 * DAY);
    expect(decision.shouldResume).toBe(false);
    expect(decision.reason).toBe("max_resumes_exhausted");
    expect(decision.resumeCount).toBe(DEFAULT_RESUME_POLICY.maxAutoResumes);
  });

  it("DEFAULT_RESUME_POLICY sticks to finding-prescribed values", () => {
    expect(DEFAULT_RESUME_POLICY.autoResumeAfterMs).toBe(3 * DAY);
    expect(DEFAULT_RESUME_POLICY.maxAutoResumes).toBe(3);
  });
});
