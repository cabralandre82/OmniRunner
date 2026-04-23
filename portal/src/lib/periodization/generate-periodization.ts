/**
 * L23-06 — Pure periodization generator.
 *
 * Given a {@link RaceTarget}, a {@link AthleteLevel} and a desired
 * total number of weeks, produce a {@link PeriodizationPlan} with
 * base → build → peak → taper blocks whose week numbers are
 * contiguous and exhaustive (every week 1..totalWeeks appears in
 * exactly one block). The generator is deterministic, has zero I/O
 * and no platform dependencies so it is fully unit-testable.
 *
 * Coach-facing contract:
 *   - A coach picks `raceTarget + totalWeeks + athleteLevel` in the
 *     wizard. The portal calls this function to preview the block
 *     layout, then materialises it into `training_plan_weeks` rows.
 *   - Coaches edit blocks (not individual workouts) — this is the
 *     scaling insight from the finding's "coach edita blocks" line.
 *
 * Invariants (enforced by `assertPeriodizationPlanValid`):
 *   1. block week numbers are contiguous 1..totalWeeks
 *   2. no week appears in two blocks
 *   3. first block is always `base`
 *   4. last block is always `taper`
 *   5. block directly before the taper is either `peak` or `build`
 *   6. each block has at least one week
 *   7. every weeklyVolumeKm is strictly positive
 */

import {
  ATHLETE_LEVELS,
  AthleteLevel,
  PeriodizationBlock,
  PeriodizationPlan,
  RACE_SPECS,
  RACE_TARGETS,
  RaceSpec,
  RaceTarget,
} from "./types";

export interface GeneratePeriodizationInput {
  raceTarget: RaceTarget;
  totalWeeks: number;
  athleteLevel: AthleteLevel;
}

export class PeriodizationInputError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(`[${code}] ${message}`);
    this.name = "PeriodizationInputError";
    this.code = code;
  }
}

export function generatePeriodization(
  input: GeneratePeriodizationInput,
): PeriodizationPlan {
  const { raceTarget, totalWeeks, athleteLevel } = input;

  if (!RACE_TARGETS.includes(raceTarget)) {
    throw new PeriodizationInputError(
      "UNKNOWN_RACE_TARGET",
      `Unknown race target "${raceTarget}". Expected one of ${RACE_TARGETS.join(", ")}.`,
    );
  }
  if (!ATHLETE_LEVELS.includes(athleteLevel)) {
    throw new PeriodizationInputError(
      "UNKNOWN_ATHLETE_LEVEL",
      `Unknown athlete level "${athleteLevel}". Expected one of ${ATHLETE_LEVELS.join(", ")}.`,
    );
  }
  if (!Number.isInteger(totalWeeks)) {
    throw new PeriodizationInputError(
      "TOTAL_WEEKS_NOT_INT",
      `totalWeeks must be an integer; got ${totalWeeks}.`,
    );
  }
  const spec = RACE_SPECS[raceTarget];
  if (totalWeeks < spec.minTotalWeeks || totalWeeks > spec.maxTotalWeeks) {
    throw new PeriodizationInputError(
      "TOTAL_WEEKS_OUT_OF_RANGE",
      `totalWeeks must be between ${spec.minTotalWeeks} and ${spec.maxTotalWeeks} for ${spec.label}; got ${totalWeeks}.`,
    );
  }

  const { baseLen, buildLen, peakLen, taperLen } = partitionWeeks(
    totalWeeks,
    spec,
  );
  const peakWeeklyKm = spec.peakWeeklyKmByLevel[athleteLevel];

  const blocks: PeriodizationBlock[] = [];
  let cursor = 1;

  blocks.push(
    buildBlock({
      cycleType: "base",
      startWeek: cursor,
      length: baseLen,
      focusText: focusFor("base", spec),
      weeklyVolumeKm: round1(peakWeeklyKm * 0.55),
      intensityHint: intensityHintFor("base", athleteLevel),
    }),
  );
  cursor += baseLen;

  if (buildLen > 0) {
    blocks.push(
      buildBlock({
        cycleType: "build",
        startWeek: cursor,
        length: buildLen,
        focusText: focusFor("build", spec),
        weeklyVolumeKm: round1(peakWeeklyKm * 0.8),
        intensityHint: intensityHintFor("build", athleteLevel),
      }),
    );
    cursor += buildLen;
  }

  blocks.push(
    buildBlock({
      cycleType: "peak",
      startWeek: cursor,
      length: peakLen,
      focusText: focusFor("peak", spec),
      weeklyVolumeKm: peakWeeklyKm,
      intensityHint: intensityHintFor("peak", athleteLevel),
    }),
  );
  cursor += peakLen;

  blocks.push(
    buildBlock({
      cycleType: "taper",
      startWeek: cursor,
      length: taperLen,
      focusText: focusFor("taper", spec),
      weeklyVolumeKm: round1(peakWeeklyKm * 0.5),
      intensityHint: intensityHintFor("taper", athleteLevel),
    }),
  );
  cursor += taperLen;

  const plan: PeriodizationPlan = {
    raceTarget,
    totalWeeks,
    athleteLevel,
    blocks,
  };
  assertPeriodizationPlanValid(plan);
  return plan;
}

interface Partition {
  baseLen: number;
  buildLen: number;
  peakLen: number;
  taperLen: number;
}

function partitionWeeks(totalWeeks: number, spec: RaceSpec): Partition {
  const taperLen = Math.min(spec.taperWeeks, Math.max(1, totalWeeks - 3));
  const peakLen = Math.min(spec.peakWeeks, Math.max(1, totalWeeks - taperLen - 2));
  const remaining = totalWeeks - taperLen - peakLen;
  if (remaining < 2) {
    throw new PeriodizationInputError(
      "TOTAL_WEEKS_TOO_SHORT",
      `totalWeeks=${totalWeeks} cannot fit taper(${taperLen})+peak(${peakLen})+base(>=1)+build(>=0) for ${spec.label}.`,
    );
  }
  const baseLen = Math.max(2, Math.round(remaining * (spec.baseFraction / (spec.baseFraction + spec.buildFraction))));
  const buildLen = remaining - baseLen;
  if (buildLen < 0) {
    throw new PeriodizationInputError(
      "PARTITION_FAILED",
      `base(${baseLen}) exceeds remaining(${remaining}) for ${spec.label} @ ${totalWeeks}w.`,
    );
  }
  return { baseLen, buildLen, peakLen, taperLen };
}

interface BuildBlockArgs {
  cycleType: PeriodizationBlock["cycleType"];
  startWeek: number;
  length: number;
  focusText: string;
  weeklyVolumeKm: number;
  intensityHint: string;
}

function buildBlock(args: BuildBlockArgs): PeriodizationBlock {
  const weekNumbers: number[] = [];
  for (let i = 0; i < args.length; i += 1) {
    weekNumbers.push(args.startWeek + i);
  }
  return {
    cycleType: args.cycleType,
    weekNumbers,
    focusText: args.focusText,
    weeklyVolumeKm: args.weeklyVolumeKm,
    intensityHint: args.intensityHint,
  };
}

function focusFor(
  cycle: PeriodizationBlock["cycleType"],
  spec: RaceSpec,
): string {
  switch (cycle) {
    case "base":
      return `Construção de base aeróbica para ${spec.label} — volume fácil, poucos estímulos.`;
    case "build":
      return `Introdução de trabalho de limiar e tempo para ${spec.label}.`;
    case "peak":
      return `Pico de volume e intensidade específica para ${spec.label}.`;
    case "taper":
      return `Afinamento pré-${spec.label} — volume reduz 40-50 %, intensidade preservada.`;
    default:
      return `${cycle} block for ${spec.label}.`;
  }
}

function intensityHintFor(
  cycle: PeriodizationBlock["cycleType"],
  level: AthleteLevel,
): string {
  const levelSuffix = level === "beginner"
    ? "(ritmo conversacional sempre)"
    : level === "intermediate"
      ? "(inclua 1 sessão de qualidade)"
      : "(até 3 sessões de qualidade/semana)";
  switch (cycle) {
    case "base":
      return `Z1-Z2 predominante ${levelSuffix}`;
    case "build":
      return `Z2-Z3 com tempo runs ${levelSuffix}`;
    case "peak":
      return `Z3-Z4 com sessões de limiar e VO2 ${levelSuffix}`;
    case "taper":
      return `Z2 com 1-2 estímulos curtos no ritmo de prova ${levelSuffix}`;
    default:
      return `Zona variada ${levelSuffix}`;
  }
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

export function assertPeriodizationPlanValid(plan: PeriodizationPlan): void {
  if (plan.blocks.length === 0) {
    throw new PeriodizationInputError(
      "PLAN_HAS_NO_BLOCKS",
      `Plan for ${plan.raceTarget}@${plan.totalWeeks}w has no blocks.`,
    );
  }

  const seen = new Set<number>();
  for (const block of plan.blocks) {
    if (block.weekNumbers.length === 0) {
      throw new PeriodizationInputError(
        "EMPTY_BLOCK",
        `Block ${block.cycleType} has no weeks.`,
      );
    }
    if (!Number.isFinite(block.weeklyVolumeKm) || block.weeklyVolumeKm <= 0) {
      throw new PeriodizationInputError(
        "NONPOSITIVE_VOLUME",
        `Block ${block.cycleType} has non-positive weeklyVolumeKm=${block.weeklyVolumeKm}.`,
      );
    }
    for (const wk of block.weekNumbers) {
      if (seen.has(wk)) {
        throw new PeriodizationInputError(
          "OVERLAPPING_WEEKS",
          `Week ${wk} appears in more than one block.`,
        );
      }
      seen.add(wk);
    }
  }

  if (seen.size !== plan.totalWeeks) {
    throw new PeriodizationInputError(
      "WEEKS_NOT_CONTIGUOUS",
      `Plan covers ${seen.size} weeks but totalWeeks=${plan.totalWeeks}.`,
    );
  }
  for (let wk = 1; wk <= plan.totalWeeks; wk += 1) {
    if (!seen.has(wk)) {
      throw new PeriodizationInputError(
        "WEEKS_NOT_CONTIGUOUS",
        `Week ${wk} is not covered by any block.`,
      );
    }
  }

  if (plan.blocks[0].cycleType !== "base") {
    throw new PeriodizationInputError(
      "FIRST_BLOCK_NOT_BASE",
      `First block must be base; got ${plan.blocks[0].cycleType}.`,
    );
  }
  const last = plan.blocks[plan.blocks.length - 1];
  if (last.cycleType !== "taper") {
    throw new PeriodizationInputError(
      "LAST_BLOCK_NOT_TAPER",
      `Last block must be taper; got ${last.cycleType}.`,
    );
  }
  if (plan.blocks.length >= 2) {
    const penultimate = plan.blocks[plan.blocks.length - 2];
    if (penultimate.cycleType !== "peak" && penultimate.cycleType !== "build") {
      throw new PeriodizationInputError(
        "PENULTIMATE_BLOCK_INVALID",
        `Block before taper must be peak or build; got ${penultimate.cycleType}.`,
      );
    }
  }
}

export function summarisePlan(plan: PeriodizationPlan): string {
  const parts = plan.blocks.map(
    (b) =>
      `${b.cycleType}(${b.weekNumbers.length}w@${b.weeklyVolumeKm}km)`,
  );
  return `${plan.raceTarget}/${plan.athleteLevel}/${plan.totalWeeks}w: ${parts.join(" → ")}`;
}
