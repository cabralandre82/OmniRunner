import { describe, expect, it } from "vitest";
import { computeNextAttemptAt } from "./policy";
import { DEFAULT_RETRY_POLICY, type RetryPolicy } from "./types";

const policy: RetryPolicy = DEFAULT_RETRY_POLICY;

describe("computeNextAttemptAt", () => {
  it("returns now for attempts <= 0 + zero jitter", () => {
    const out = computeNextAttemptAt({
      attempts: 0, now: 100, policy, random: () => 0.5,
    });
    expect(out).toBe(100 + policy.baseDelayMs);
  });

  it("doubles delay on each attempt up to the cap", () => {
    const noJitter: RetryPolicy = { ...policy, jitterRatio: 0 };
    const a = computeNextAttemptAt({ attempts: 1, now: 0, policy: noJitter });
    const b = computeNextAttemptAt({ attempts: 2, now: 0, policy: noJitter });
    const c = computeNextAttemptAt({ attempts: 3, now: 0, policy: noJitter });
    expect(a).toBe(policy.baseDelayMs);
    expect(b).toBe(policy.baseDelayMs * 2);
    expect(c).toBe(policy.baseDelayMs * 4);
  });

  it("respects maxDelayMs cap", () => {
    const noJitter: RetryPolicy = { ...policy, jitterRatio: 0 };
    const out = computeNextAttemptAt({
      attempts: 20, now: 0, policy: noJitter,
    });
    expect(out).toBe(policy.maxDelayMs);
  });

  it("jitter stays within ±jitterRatio band", () => {
    const samples = 200;
    const attempts = 3;
    const min = policy.baseDelayMs * 4 * (1 - policy.jitterRatio);
    const max = policy.baseDelayMs * 4 * (1 + policy.jitterRatio);
    for (let i = 0; i < samples; i += 1) {
      const out = computeNextAttemptAt({
        attempts,
        now: 0,
        policy,
        random: () => Math.random(),
      });
      expect(out).toBeGreaterThanOrEqual(Math.floor(min));
      expect(out).toBeLessThanOrEqual(Math.ceil(max));
    }
  });

  it("never returns a negative timestamp", () => {
    const out = computeNextAttemptAt({
      attempts: 1, now: 0, policy, random: () => 0,
    });
    expect(out).toBeGreaterThanOrEqual(0);
  });
});
