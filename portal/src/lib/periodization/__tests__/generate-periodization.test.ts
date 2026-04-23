/**
 * L23-06 — Unit tests for the pure periodization generator.
 *
 * These tests treat the generator as a coach-facing contract: if any
 * of these shapes change, a coach's training plan preview also
 * changes, so every mutation must be deliberate and signed off by a
 * code-owner on the coaching surface.
 */

import { describe, it, expect } from "vitest";
import {
  assertPeriodizationPlanValid,
  generatePeriodization,
  PeriodizationInputError,
} from "../generate-periodization";
import {
  ATHLETE_LEVELS,
  PeriodizationPlan,
  RACE_SPECS,
  RACE_TARGETS,
} from "../types";

describe("generatePeriodization — contract", () => {
  it("rejects unknown race targets", () => {
    expect(() =>
      generatePeriodization({
        raceTarget: "ultraMarathon" as unknown as "marathon",
        totalWeeks: 16,
        athleteLevel: "intermediate",
      }),
    ).toThrowError(PeriodizationInputError);
  });

  it("rejects unknown athlete levels", () => {
    expect(() =>
      generatePeriodization({
        raceTarget: "tenK",
        totalWeeks: 12,
        athleteLevel: "elite" as unknown as "advanced",
      }),
    ).toThrowError(PeriodizationInputError);
  });

  it("rejects non-integer totalWeeks", () => {
    expect(() =>
      generatePeriodization({
        raceTarget: "halfMarathon",
        totalWeeks: 12.5,
        athleteLevel: "intermediate",
      }),
    ).toThrowError(/TOTAL_WEEKS_NOT_INT/);
  });

  it("rejects totalWeeks below spec.minTotalWeeks", () => {
    expect(() =>
      generatePeriodization({
        raceTarget: "marathon",
        totalWeeks: 10,
        athleteLevel: "intermediate",
      }),
    ).toThrowError(/TOTAL_WEEKS_OUT_OF_RANGE/);
  });

  it("rejects totalWeeks above spec.maxTotalWeeks", () => {
    expect(() =>
      generatePeriodization({
        raceTarget: "fiveK",
        totalWeeks: 30,
        athleteLevel: "intermediate",
      }),
    ).toThrowError(/TOTAL_WEEKS_OUT_OF_RANGE/);
  });
});

describe("generatePeriodization — half marathon 12 weeks (finding example)", () => {
  const plan = generatePeriodization({
    raceTarget: "halfMarathon",
    totalWeeks: 12,
    athleteLevel: "intermediate",
  });

  it("covers all 12 weeks contiguously with no overlap", () => {
    const weeks = plan.blocks.flatMap((b) => b.weekNumbers).sort((a, b) => a - b);
    expect(weeks).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  });

  it("begins with base and ends with taper", () => {
    expect(plan.blocks[0].cycleType).toBe("base");
    expect(plan.blocks[plan.blocks.length - 1].cycleType).toBe("taper");
  });

  it("includes at least one build and one peak block", () => {
    const kinds = plan.blocks.map((b) => b.cycleType);
    expect(kinds).toContain("build");
    expect(kinds).toContain("peak");
  });

  it("taper length matches spec (2 weeks for halfMarathon)", () => {
    const taper = plan.blocks.find((b) => b.cycleType === "taper")!;
    expect(taper.weekNumbers.length).toBe(2);
  });

  it("peak weekly volume equals peakWeeklyKmByLevel.intermediate", () => {
    const peak = plan.blocks.find((b) => b.cycleType === "peak")!;
    expect(peak.weeklyVolumeKm).toBe(
      RACE_SPECS.halfMarathon.peakWeeklyKmByLevel.intermediate,
    );
  });

  it("base volume < build volume < peak volume", () => {
    const base = plan.blocks.find((b) => b.cycleType === "base")!;
    const build = plan.blocks.find((b) => b.cycleType === "build")!;
    const peak = plan.blocks.find((b) => b.cycleType === "peak")!;
    expect(base.weeklyVolumeKm).toBeLessThan(build.weeklyVolumeKm);
    expect(build.weeklyVolumeKm).toBeLessThan(peak.weeklyVolumeKm);
  });

  it("taper volume is strictly less than peak volume", () => {
    const peak = plan.blocks.find((b) => b.cycleType === "peak")!;
    const taper = plan.blocks.find((b) => b.cycleType === "taper")!;
    expect(taper.weeklyVolumeKm).toBeLessThan(peak.weeklyVolumeKm);
  });

  it("focus text mentions the race label", () => {
    for (const block of plan.blocks) {
      expect(block.focusText).toContain("Meia-maratona");
    }
  });
});

describe("generatePeriodization — invariants across entire matrix", () => {
  it("every target × level × valid totalWeeks produces a valid plan", () => {
    for (const target of RACE_TARGETS) {
      const spec = RACE_SPECS[target];
      for (const level of ATHLETE_LEVELS) {
        for (
          let weeks = spec.minTotalWeeks;
          weeks <= spec.maxTotalWeeks;
          weeks += 1
        ) {
          const plan = generatePeriodization({
            raceTarget: target,
            totalWeeks: weeks,
            athleteLevel: level,
          });
          expect(() => assertPeriodizationPlanValid(plan)).not.toThrow();
          const covered = plan.blocks.flatMap((b) => b.weekNumbers);
          expect(new Set(covered).size).toBe(weeks);
          expect(plan.blocks[0].cycleType).toBe("base");
          expect(plan.blocks[plan.blocks.length - 1].cycleType).toBe("taper");
        }
      }
    }
  });

  it("every plan's block peak matches spec for the given level", () => {
    for (const target of RACE_TARGETS) {
      const spec = RACE_SPECS[target];
      for (const level of ATHLETE_LEVELS) {
        const plan = generatePeriodization({
          raceTarget: target,
          totalWeeks: spec.minTotalWeeks,
          athleteLevel: level,
        });
        const peak = plan.blocks.find((b) => b.cycleType === "peak");
        expect(peak).toBeTruthy();
        expect(peak!.weeklyVolumeKm).toBe(spec.peakWeeklyKmByLevel[level]);
      }
    }
  });

  it("taperWeeks honours spec.taperWeeks when totalWeeks is generous", () => {
    for (const target of RACE_TARGETS) {
      const spec = RACE_SPECS[target];
      const plan = generatePeriodization({
        raceTarget: target,
        totalWeeks: Math.min(spec.maxTotalWeeks, spec.minTotalWeeks + 4),
        athleteLevel: "intermediate",
      });
      const taper = plan.blocks.find((b) => b.cycleType === "taper")!;
      expect(taper.weekNumbers.length).toBe(spec.taperWeeks);
    }
  });

  it("beginner level yields strictly lower peak volume than advanced", () => {
    for (const target of RACE_TARGETS) {
      const spec = RACE_SPECS[target];
      const weeks = spec.minTotalWeeks;
      const beginner = generatePeriodization({
        raceTarget: target,
        totalWeeks: weeks,
        athleteLevel: "beginner",
      });
      const advanced = generatePeriodization({
        raceTarget: target,
        totalWeeks: weeks,
        athleteLevel: "advanced",
      });
      const beginnerPeak = beginner.blocks.find((b) => b.cycleType === "peak")!;
      const advancedPeak = advanced.blocks.find((b) => b.cycleType === "peak")!;
      expect(beginnerPeak.weeklyVolumeKm).toBeLessThan(
        advancedPeak.weeklyVolumeKm,
      );
    }
  });
});

describe("assertPeriodizationPlanValid — rejects malformed plans", () => {
  it("rejects a plan that skips a week", () => {
    const plan: PeriodizationPlan = {
      raceTarget: "tenK",
      totalWeeks: 10,
      athleteLevel: "intermediate",
      blocks: [
        {
          cycleType: "base",
          weekNumbers: [1, 2, 3],
          focusText: "base",
          weeklyVolumeKm: 30,
          intensityHint: "Z1",
        },
        {
          cycleType: "build",
          weekNumbers: [5, 6],
          focusText: "build",
          weeklyVolumeKm: 45,
          intensityHint: "Z2",
        },
        {
          cycleType: "peak",
          weekNumbers: [7, 8, 9],
          focusText: "peak",
          weeklyVolumeKm: 60,
          intensityHint: "Z3",
        },
        {
          cycleType: "taper",
          weekNumbers: [10],
          focusText: "taper",
          weeklyVolumeKm: 30,
          intensityHint: "Z2",
        },
      ],
    };
    expect(() => assertPeriodizationPlanValid(plan)).toThrowError(
      /WEEKS_NOT_CONTIGUOUS|Week 4/,
    );
  });

  it("rejects a plan that does not start with base", () => {
    const plan: PeriodizationPlan = {
      raceTarget: "fiveK",
      totalWeeks: 6,
      athleteLevel: "beginner",
      blocks: [
        {
          cycleType: "build",
          weekNumbers: [1, 2, 3, 4],
          focusText: "build",
          weeklyVolumeKm: 20,
          intensityHint: "Z2",
        },
        {
          cycleType: "peak",
          weekNumbers: [5],
          focusText: "peak",
          weeklyVolumeKm: 25,
          intensityHint: "Z3",
        },
        {
          cycleType: "taper",
          weekNumbers: [6],
          focusText: "taper",
          weeklyVolumeKm: 15,
          intensityHint: "Z2",
        },
      ],
    };
    expect(() => assertPeriodizationPlanValid(plan)).toThrowError(
      /FIRST_BLOCK_NOT_BASE/,
    );
  });

  it("rejects a plan that does not end with taper", () => {
    const plan: PeriodizationPlan = {
      raceTarget: "fiveK",
      totalWeeks: 6,
      athleteLevel: "beginner",
      blocks: [
        {
          cycleType: "base",
          weekNumbers: [1, 2, 3, 4],
          focusText: "base",
          weeklyVolumeKm: 15,
          intensityHint: "Z1",
        },
        {
          cycleType: "peak",
          weekNumbers: [5, 6],
          focusText: "peak",
          weeklyVolumeKm: 25,
          intensityHint: "Z3",
        },
      ],
    };
    expect(() => assertPeriodizationPlanValid(plan)).toThrowError(
      /LAST_BLOCK_NOT_TAPER/,
    );
  });

  it("rejects a plan with a non-positive weekly volume", () => {
    const plan: PeriodizationPlan = {
      raceTarget: "fiveK",
      totalWeeks: 6,
      athleteLevel: "beginner",
      blocks: [
        {
          cycleType: "base",
          weekNumbers: [1, 2, 3],
          focusText: "base",
          weeklyVolumeKm: 0,
          intensityHint: "Z1",
        },
        {
          cycleType: "peak",
          weekNumbers: [4, 5],
          focusText: "peak",
          weeklyVolumeKm: 20,
          intensityHint: "Z3",
        },
        {
          cycleType: "taper",
          weekNumbers: [6],
          focusText: "taper",
          weeklyVolumeKm: 12,
          intensityHint: "Z2",
        },
      ],
    };
    expect(() => assertPeriodizationPlanValid(plan)).toThrowError(
      /NONPOSITIVE_VOLUME/,
    );
  });
});
