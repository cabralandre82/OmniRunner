/**
 * validate.ts — Semantic validation for parsed workout blocks.
 *
 * Context — L05-23
 * -----------------
 * The AI parser (parse-workout/route.ts) returns blocks that pass JSON
 * schema validation but may still be semantically broken:
 *   - `repeat` with no inner active block.
 *   - `repeat_count` of 1 (nothing to repeat).
 *   - `target_pace_min` > `target_pace_max` (inverted pace range). The DB
 *     has a CHECK constraint but the 23514 error surfaced in the portal
 *     as a generic 500 — no hint which block is wrong.
 *   - A block with BOTH `duration_seconds` AND `distance_meters` (FIT
 *     encoder picks one and silently drops the other).
 *   - A block with NEITHER (coach meant "free run" but the block has no
 *     trigger → watch step never completes).
 *   - `estimated_distance_km` 40% off from the block sum (AI hallucination).
 *
 * This module provides a single entry point `validateWorkoutBlocks` that
 * returns structured errors and warnings. Errors produce HTTP 422;
 * warnings produce 200 OK with `warnings[]` in the response so the
 * portal UI can surface an amber banner.
 *
 * The module is DB-agnostic — callers pass parsed JSON. It's used by:
 *   - parse-workout/route.ts (reject bad AI output BEFORE showing to coach).
 *   - (future) week-templates route handlers, INSERT guard.
 */

import type { BlockType } from "./expand-repeats";

/** A parsed block as it arrives from the AI parser or user input. */
export interface ValidatableBlock {
  block_type: BlockType;
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_min_sec_per_km: number | null;
  target_pace_max_sec_per_km: number | null;
  target_hr_min: number | null;
  target_hr_max: number | null;
  target_hr_zone: number | null;
  repeat_count: number | null;
}

export type ValidationCode =
  | "invalid_block_type"
  | "repeat_needs_count"
  | "repeat_count_too_small"
  | "repeat_empty_group"
  | "repeat_unclosed"
  | "repeat_orphan_end"
  | "repeat_nested_unsupported"
  | "trigger_missing"
  | "trigger_both"
  | "pace_inverted"
  | "pace_partial"
  | "hr_inverted"
  | "hr_partial"
  | "hr_zone_out_of_range"
  | "repeat_must_have_active_block";

export interface ValidationIssue {
  code: ValidationCode;
  message: string;
  blockIndex: number;
  field?: string;
}

export interface EstimateDrift {
  /** fraction (0.0..1.0) by which sum differs from AI estimate. */
  deltaRatio: number;
  sumDistanceKm: number;
  estimateDistanceKm: number;
  sumDurationMin: number;
  estimateDurationMin: number;
}

export interface ValidationResult {
  ok: boolean;
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
  estimateDrift: EstimateDrift | null;
}

const VALID_BLOCK_TYPES: readonly BlockType[] = [
  "warmup",
  "interval",
  "recovery",
  "cooldown",
  "steady",
  "rest",
  "repeat",
  "repeat_end",
];

/** Blocks whose job is to contribute to training load (not structural markers). */
const ACTIVE_TYPES: readonly BlockType[] = [
  "warmup",
  "interval",
  "recovery",
  "cooldown",
  "steady",
  "rest",
];

/** Blocks that NEED exactly one of (duration|distance) to give the watch a stop condition. */
const TRIGGER_REQUIRED_TYPES: readonly BlockType[] = [
  "warmup",
  "interval",
  "recovery",
  "cooldown",
  "steady",
  "rest",
];

/** ±30% is the warning threshold; ±60% is the error threshold. Empirically tuned
 *  from test runs of "corrida de 20min" where GPT frequently miscounts by ~20-25%. */
const ESTIMATE_WARN_RATIO = 0.3;
const ESTIMATE_ERROR_RATIO = 0.6;

export function validateWorkoutBlocks(
  blocks: ValidatableBlock[],
  options?: {
    estimatedDistanceKm?: number | null;
    estimatedDurationMinutes?: number | null;
  },
): ValidationResult {
  const errors: ValidationIssue[] = [];
  const warnings: ValidationIssue[] = [];

  // ─── Per-block checks ───────────────────────────────────────────────────────

  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];

    if (!VALID_BLOCK_TYPES.includes(b.block_type)) {
      errors.push({
        code: "invalid_block_type",
        message: `Bloco ${i}: block_type "${b.block_type}" fora do enum aceito (${VALID_BLOCK_TYPES.join("|")}).`,
        blockIndex: i,
        field: "block_type",
      });
      continue;
    }

    // Trigger (duration OR distance, never both, never neither — except structural)
    if (TRIGGER_REQUIRED_TYPES.includes(b.block_type)) {
      const hasDur = b.duration_seconds !== null && b.duration_seconds > 0;
      const hasDist = b.distance_meters !== null && b.distance_meters > 0;
      if (hasDur && hasDist) {
        errors.push({
          code: "trigger_both",
          message:
            `Bloco ${i} (${b.block_type}): contém duração E distância simultaneamente. ` +
            "O relógio segue APENAS um critério (tempo OU distância); o outro é silenciosamente ignorado. " +
            "Escolha um.",
          blockIndex: i,
        });
      } else if (!hasDur && !hasDist) {
        errors.push({
          code: "trigger_missing",
          message:
            `Bloco ${i} (${b.block_type}): não tem duração nem distância. ` +
            "O relógio nunca avança para o próximo passo (loop infinito no step).",
          blockIndex: i,
        });
      }
    }

    // Pace range coherence
    const pMin = b.target_pace_min_sec_per_km;
    const pMax = b.target_pace_max_sec_per_km;
    if ((pMin === null) !== (pMax === null)) {
      errors.push({
        code: "pace_partial",
        message:
          `Bloco ${i}: target_pace_min e target_pace_max devem ambos estar preenchidos, ou ambos null.`,
        blockIndex: i,
        field: pMin === null ? "target_pace_min_sec_per_km" : "target_pace_max_sec_per_km",
      });
    } else if (pMin !== null && pMax !== null && pMin > pMax) {
      errors.push({
        code: "pace_inverted",
        message:
          `Bloco ${i}: target_pace_min (${pMin}s/km, mais RÁPIDO) é maior que target_pace_max (${pMax}s/km, mais LENTO). ` +
          "Pace em sec/km é invertido: menor número = mais rápido. Troque os valores.",
        blockIndex: i,
        field: "target_pace_min_sec_per_km",
      });
    }

    // HR range coherence
    const hrMin = b.target_hr_min;
    const hrMax = b.target_hr_max;
    if ((hrMin === null) !== (hrMax === null)) {
      errors.push({
        code: "hr_partial",
        message: `Bloco ${i}: target_hr_min e target_hr_max devem ambos estar preenchidos, ou ambos null.`,
        blockIndex: i,
        field: hrMin === null ? "target_hr_min" : "target_hr_max",
      });
    } else if (hrMin !== null && hrMax !== null && hrMin > hrMax) {
      errors.push({
        code: "hr_inverted",
        message: `Bloco ${i}: target_hr_min (${hrMin}) > target_hr_max (${hrMax}). Troque.`,
        blockIndex: i,
        field: "target_hr_min",
      });
    }

    // HR zone sanity
    if (b.target_hr_zone !== null && (b.target_hr_zone < 1 || b.target_hr_zone > 5)) {
      errors.push({
        code: "hr_zone_out_of_range",
        message: `Bloco ${i}: target_hr_zone=${b.target_hr_zone} fora do range 1..5.`,
        blockIndex: i,
        field: "target_hr_zone",
      });
    }

    // Per-repeat block: repeat_count sanity.
    if (b.block_type === "repeat") {
      if (b.repeat_count === null) {
        errors.push({
          code: "repeat_needs_count",
          message: `Bloco ${i} (repeat): repeat_count é obrigatório e deve ser ≥ 2.`,
          blockIndex: i,
          field: "repeat_count",
        });
      } else if (b.repeat_count < 2) {
        errors.push({
          code: "repeat_count_too_small",
          message:
            `Bloco ${i} (repeat): repeat_count=${b.repeat_count}. ` +
            "Repetições com count < 2 são inúteis. Use ≥ 2 ou remova o marker.",
          blockIndex: i,
          field: "repeat_count",
        });
      }
    }
  }

  // ─── Structural checks (repeat / repeat_end balance and content) ────────────

  let openGroupOpener: number | null = null;
  let openGroupActiveCount = 0;

  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];

    if (b.block_type === "repeat") {
      if (openGroupOpener !== null) {
        errors.push({
          code: "repeat_nested_unsupported",
          message: `Bloco ${i}: repeat aninhado dentro do grupo aberto em ${openGroupOpener}. Feche o externo com repeat_end primeiro.`,
          blockIndex: i,
        });
      } else {
        openGroupOpener = i;
        openGroupActiveCount = 0;
      }
      continue;
    }

    if (b.block_type === "repeat_end") {
      if (openGroupOpener === null) {
        errors.push({
          code: "repeat_orphan_end",
          message: `Bloco ${i}: repeat_end sem um repeat aberto precedente.`,
          blockIndex: i,
        });
      } else {
        if (openGroupActiveCount === 0) {
          errors.push({
            code: "repeat_must_have_active_block",
            message:
              `Bloco ${openGroupOpener} (repeat) não contém nenhum bloco ativo antes do repeat_end no ${i}. ` +
              "Adicione pelo menos um interval/recovery/etc, ou remova o par repeat/repeat_end.",
            blockIndex: openGroupOpener,
          });
        }
        openGroupOpener = null;
        openGroupActiveCount = 0;
      }
      continue;
    }

    if (openGroupOpener !== null && ACTIVE_TYPES.includes(b.block_type)) {
      openGroupActiveCount++;
    }
  }

  if (openGroupOpener !== null) {
    errors.push({
      code: "repeat_unclosed",
      message:
        `Bloco ${openGroupOpener} (repeat) não tem repeat_end correspondente antes do fim do treino. ` +
        "Feche o grupo explicitamente.",
      blockIndex: openGroupOpener,
    });
  }

  // ─── Estimate drift (warning only) ──────────────────────────────────────────

  const drift = computeEstimateDrift(blocks, options);
  if (drift) {
    if (drift.deltaRatio > ESTIMATE_ERROR_RATIO) {
      errors.push({
        code: "invalid_block_type", // reused code — drift is a class-of-error
        message:
          `Soma dos blocos divergente do estimado em ${(drift.deltaRatio * 100).toFixed(0)}% ` +
          `(blocks=${drift.sumDistanceKm.toFixed(1)}km/${drift.sumDurationMin.toFixed(0)}min vs ` +
          `estimate=${drift.estimateDistanceKm.toFixed(1)}km/${drift.estimateDurationMin.toFixed(0)}min). ` +
          "Provável alucinação da IA — revise manualmente.",
        blockIndex: -1,
      });
    } else if (drift.deltaRatio > ESTIMATE_WARN_RATIO) {
      warnings.push({
        code: "invalid_block_type",
        message:
          `Soma dos blocos (${drift.sumDistanceKm.toFixed(1)}km/${drift.sumDurationMin.toFixed(0)}min) ` +
          `difere do estimado (${drift.estimateDistanceKm.toFixed(1)}km/${drift.estimateDurationMin.toFixed(0)}min) ` +
          `em ${(drift.deltaRatio * 100).toFixed(0)}%. Revise se o valor faz sentido.`,
        blockIndex: -1,
      });
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    estimateDrift: drift,
  };
}

/**
 * Compute how much the AI's estimated totals diverge from the sum of the blocks.
 * Returns null if there's not enough data to compare (no estimate OR no blocks
 * contributed to the sum).
 *
 * We compare both distance and duration and pick the MAX relative delta
 * (worst of the two) so a wildly-off distance with a correct duration still
 * triggers the warning.
 *
 * Does NOT depend on expandRepeats because it runs BEFORE structural fixes
 * (repeat_end insertion) may happen. Works on the raw per-block sums + a
 * best-effort multiplier reconstruction.
 */
function computeEstimateDrift(
  blocks: ValidatableBlock[],
  options?: {
    estimatedDistanceKm?: number | null;
    estimatedDurationMinutes?: number | null;
  },
): EstimateDrift | null {
  if (!options) return null;
  const estDistKm = options.estimatedDistanceKm ?? null;
  const estDurMin = options.estimatedDurationMinutes ?? null;
  if (estDistKm === null && estDurMin === null) return null;

  let sumM = 0;
  let sumS = 0;
  let multiplier = 1;
  let inRepeat = false;

  for (const b of blocks) {
    if (b.block_type === "repeat") {
      multiplier = Math.max(1, b.repeat_count ?? 1);
      inRepeat = true;
      continue;
    }
    if (b.block_type === "repeat_end") {
      multiplier = 1;
      inRepeat = false;
      continue;
    }
    const m = inRepeat ? multiplier : 1;
    if (b.block_type !== "rest" && b.distance_meters) {
      sumM += b.distance_meters * m;
    }
    if (b.duration_seconds) {
      sumS += b.duration_seconds * m;
    }
  }

  const sumDistanceKm = sumM / 1000;
  const sumDurationMin = sumS / 60;

  // Only compare a dimension when BOTH the estimate AND the block sum are
  // positive. A distance-only workout (35 × 500m without duration targets)
  // legitimately has sum_duration = 0 — comparing that to the AI's time
  // estimate would flag every legitimate pace-based intervalado as hallucinated.
  let deltaRatio = 0;
  if (estDistKm !== null && estDistKm > 0 && sumM > 0) {
    deltaRatio = Math.max(deltaRatio, Math.abs(sumDistanceKm - estDistKm) / estDistKm);
  }
  if (estDurMin !== null && estDurMin > 0 && sumS > 0) {
    deltaRatio = Math.max(deltaRatio, Math.abs(sumDurationMin - estDurMin) / estDurMin);
  }

  if (sumM === 0 && sumS === 0) return null;

  return {
    deltaRatio,
    sumDistanceKm,
    estimateDistanceKm: estDistKm ?? 0,
    sumDurationMin,
    estimateDurationMin: estDurMin ?? 0,
  };
}
