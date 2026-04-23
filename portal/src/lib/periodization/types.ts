/**
 * L23-06 — Periodization template value objects.
 *
 * Coach-facing wizard produces a {@link PeriodizationPlan} that the
 * portal materialises into `training_plan_weeks` rows (cycle_type
 * column already exists, see `20260407000000_training_plan_module.sql`).
 *
 * All types in this module are plain JSON-serialisable so they can
 * ride between the wizard route, the portal UI and integration
 * tests without any platform binding.
 */

export type RaceTarget =
  | "fiveK"
  | "tenK"
  | "halfMarathon"
  | "marathon";

export type AthleteLevel = "beginner" | "intermediate" | "advanced";

export type CycleType =
  | "base"
  | "build"
  | "peak"
  | "taper"
  | "recovery"
  | "test";

export interface PeriodizationBlock {
  cycleType: CycleType;
  weekNumbers: number[];
  focusText: string;
  weeklyVolumeKm: number;
  intensityHint: string;
}

export interface PeriodizationPlan {
  raceTarget: RaceTarget;
  totalWeeks: number;
  athleteLevel: AthleteLevel;
  blocks: PeriodizationBlock[];
}

export interface RaceSpec {
  target: RaceTarget;
  label: string;
  distanceKm: number;
  taperWeeks: number;
  peakWeeks: number;
  baseFraction: number;
  buildFraction: number;
  minTotalWeeks: number;
  maxTotalWeeks: number;
  peakWeeklyKmByLevel: Record<AthleteLevel, number>;
}

/**
 * Canonical race specs. Treat this table as a contract: changing a
 * minTotalWeeks / peakWeeklyKm / taperWeeks value is a content change
 * that must go through coach-education review (see
 * `docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md` §5.1).
 */
export const RACE_SPECS: Record<RaceTarget, RaceSpec> = {
  fiveK: {
    target: "fiveK",
    label: "5K",
    distanceKm: 5,
    taperWeeks: 1,
    peakWeeks: 2,
    baseFraction: 0.4,
    buildFraction: 0.3,
    minTotalWeeks: 6,
    maxTotalWeeks: 16,
    peakWeeklyKmByLevel: {
      beginner: 25,
      intermediate: 45,
      advanced: 70,
    },
  },
  tenK: {
    target: "tenK",
    label: "10K",
    distanceKm: 10,
    taperWeeks: 1,
    peakWeeks: 3,
    baseFraction: 0.4,
    buildFraction: 0.3,
    minTotalWeeks: 8,
    maxTotalWeeks: 20,
    peakWeeklyKmByLevel: {
      beginner: 35,
      intermediate: 60,
      advanced: 90,
    },
  },
  halfMarathon: {
    target: "halfMarathon",
    label: "Meia-maratona",
    distanceKm: 21.0975,
    taperWeeks: 2,
    peakWeeks: 3,
    baseFraction: 0.4,
    buildFraction: 0.3,
    minTotalWeeks: 10,
    maxTotalWeeks: 24,
    peakWeeklyKmByLevel: {
      beginner: 45,
      intermediate: 75,
      advanced: 110,
    },
  },
  marathon: {
    target: "marathon",
    label: "Maratona",
    distanceKm: 42.195,
    taperWeeks: 3,
    peakWeeks: 4,
    baseFraction: 0.4,
    buildFraction: 0.3,
    minTotalWeeks: 14,
    maxTotalWeeks: 28,
    peakWeeklyKmByLevel: {
      beginner: 60,
      intermediate: 90,
      advanced: 130,
    },
  },
};

export const RACE_TARGETS: RaceTarget[] = [
  "fiveK",
  "tenK",
  "halfMarathon",
  "marathon",
];

export const ATHLETE_LEVELS: AthleteLevel[] = [
  "beginner",
  "intermediate",
  "advanced",
];
