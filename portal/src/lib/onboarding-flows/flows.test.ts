/**
 * L07-02 — Unit tests for role-aware onboarding flow primitives.
 */
import { describe, expect, it } from "vitest";

import {
  CANONICAL_ORDER,
  COACHING_ROLES,
  OnboardingFlowInputError,
  ONBOARDING_STEPS,
  STEP_VISIBILITY,
  buildFlowForRole,
  flowLengthForRole,
  nextStepFor,
  stepIsVisibleFor,
  validateFlowInvariants,
  type OnboardingStepId,
} from "./index";

describe("CANONICAL_ORDER / ONBOARDING_STEPS", () => {
  it("CANONICAL_ORDER mirrors ONBOARDING_STEPS", () => {
    expect([...CANONICAL_ORDER]).toEqual([...ONBOARDING_STEPS]);
  });

  it("CANONICAL_ORDER is a permutation of STEP_VISIBILITY keys", () => {
    const ordered = [...CANONICAL_ORDER].sort();
    const mapped = Object.keys(STEP_VISIBILITY).sort();
    expect(ordered).toEqual(mapped);
  });

  it("has at least 10 canonical steps", () => {
    expect(CANONICAL_ORDER.length).toBeGreaterThanOrEqual(10);
  });
});

describe("buildFlowForRole", () => {
  it("admin_master sees every step in canonical order", () => {
    const flow = buildFlowForRole("admin_master");
    expect([...flow]).toEqual([...CANONICAL_ORDER]);
  });

  it("coach sees no custody / clearing / distributions / financial", () => {
    const flow = buildFlowForRole("coach");
    expect(flow).not.toContain<OnboardingStepId>("custody");
    expect(flow).not.toContain<OnboardingStepId>("clearing");
    expect(flow).not.toContain<OnboardingStepId>("distributions");
    expect(flow).not.toContain<OnboardingStepId>("financial");
  });

  it("coach flow is strictly shorter than admin_master flow", () => {
    const master = buildFlowForRole("admin_master");
    const coach = buildFlowForRole("coach");
    expect(coach.length).toBeLessThan(master.length);
  });

  it("coach flow preserves canonical ordering", () => {
    const flow = buildFlowForRole("coach");
    const indices = flow.map((s) => CANONICAL_ORDER.indexOf(s));
    const sorted = [...indices].sort((a, b) => a - b);
    expect(indices).toEqual(sorted);
  });

  it("assistant flow is a subset of coach flow", () => {
    const coach = new Set(buildFlowForRole("coach"));
    const assistant = buildFlowForRole("assistant");
    for (const step of assistant) {
      expect(coach.has(step)).toBe(true);
    }
  });

  it("assistant does not see settings (financial config path)", () => {
    const flow = buildFlowForRole("assistant");
    expect(flow).not.toContain<OnboardingStepId>("settings");
  });

  it("throws OnboardingFlowInputError for unknown roles", () => {
    expect(() =>
      buildFlowForRole("god_mode" as unknown as "admin_master"),
    ).toThrow(OnboardingFlowInputError);
  });

  it("every role sees welcome first", () => {
    for (const role of COACHING_ROLES) {
      expect(buildFlowForRole(role)[0]).toBe("welcome");
    }
  });
});

describe("flowLengthForRole", () => {
  it("reflects buildFlowForRole length", () => {
    for (const role of COACHING_ROLES) {
      expect(flowLengthForRole(role)).toBe(buildFlowForRole(role).length);
    }
  });
});

describe("stepIsVisibleFor", () => {
  it("matches buildFlowForRole membership", () => {
    for (const role of COACHING_ROLES) {
      const flow = new Set(buildFlowForRole(role));
      for (const step of ONBOARDING_STEPS) {
        expect(stepIsVisibleFor(step, role)).toBe(flow.has(step));
      }
    }
  });
});

describe("nextStepFor", () => {
  it("returns the first step when current is null", () => {
    expect(nextStepFor(null, "admin_master")).toBe("welcome");
    expect(nextStepFor(null, "coach")).toBe("welcome");
  });

  it("returns null when current is the last step", () => {
    const flow = buildFlowForRole("admin_master");
    const last = flow[flow.length - 1];
    expect(nextStepFor(last, "admin_master")).toBeNull();
  });

  it("walks through the entire admin_master flow", () => {
    const walked: (OnboardingStepId | null)[] = [];
    let cur: OnboardingStepId | null = null;
    for (let i = 0; i < 20; i += 1) {
      cur = nextStepFor(cur, "admin_master");
      walked.push(cur);
      if (cur === null) break;
    }
    expect(walked.slice(0, -1)).toEqual(CANONICAL_ORDER);
    expect(walked[walked.length - 1]).toBeNull();
  });

  it("throws when current step is not in role's flow", () => {
    expect(() => nextStepFor("custody", "coach")).toThrow(
      OnboardingFlowInputError,
    );
  });
});

describe("validateFlowInvariants", () => {
  it("reports no issues on the canonical configuration", () => {
    expect(validateFlowInvariants()).toEqual([]);
  });
});
