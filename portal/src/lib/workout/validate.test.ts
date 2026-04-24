import { describe, it, expect } from "vitest";
import { type BlockType } from "./expand-repeats";
import { validateWorkoutBlocks, type ValidatableBlock } from "./validate";

function mk(overrides: Partial<ValidatableBlock> & { block_type: BlockType }): ValidatableBlock {
  return {
    block_type: overrides.block_type,
    duration_seconds: overrides.duration_seconds ?? null,
    distance_meters: overrides.distance_meters ?? null,
    target_pace_min_sec_per_km: overrides.target_pace_min_sec_per_km ?? null,
    target_pace_max_sec_per_km: overrides.target_pace_max_sec_per_km ?? null,
    target_hr_min: overrides.target_hr_min ?? null,
    target_hr_max: overrides.target_hr_max ?? null,
    target_hr_zone: overrides.target_hr_zone ?? null,
    repeat_count: overrides.repeat_count ?? null,
  };
}

describe("validateWorkoutBlocks — feliz path", () => {
  it("intervalado canônico válido passa sem erros", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "warmup", duration_seconds: 600 }),
      mk({ block_type: "repeat", repeat_count: 5 }),
      mk({
        block_type: "interval",
        distance_meters: 1000,
        target_pace_min_sec_per_km: 255,
        target_pace_max_sec_per_km: 275,
      }),
      mk({ block_type: "recovery", duration_seconds: 120 }),
      mk({ block_type: "repeat_end" }),
      mk({ block_type: "cooldown", duration_seconds: 600 }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it("treino contínuo simples passa", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "warmup", duration_seconds: 300 }),
      mk({ block_type: "steady", duration_seconds: 1500, target_hr_zone: 2 }),
      mk({ block_type: "cooldown", duration_seconds: 300 }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.ok).toBe(true);
  });
});

describe("validateWorkoutBlocks — trigger (duration/distance)", () => {
  it("rejeita bloco sem duração nem distância", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "interval" }), // NEITHER
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.code === "trigger_missing")).toBe(true);
  });

  it("rejeita bloco com duração E distância simultâneas", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "interval", duration_seconds: 300, distance_meters: 1000 }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.code === "trigger_both")).toBe(true);
  });

  it("não exige trigger em repeat nem repeat_end", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "repeat", repeat_count: 3 }),
      mk({ block_type: "interval", distance_meters: 400 }),
      mk({ block_type: "repeat_end" }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.ok).toBe(true);
  });
});

describe("validateWorkoutBlocks — pace range", () => {
  it("rejeita pace invertido (min numericamente > max)", () => {
    const blocks: ValidatableBlock[] = [
      mk({
        block_type: "interval",
        distance_meters: 1000,
        target_pace_min_sec_per_km: 300, // slower
        target_pace_max_sec_per_km: 250, // faster — INVERTED
      }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.code === "pace_inverted")).toBe(true);
  });

  it("rejeita pace parcialmente preenchido (só min)", () => {
    const blocks: ValidatableBlock[] = [
      mk({
        block_type: "interval",
        distance_meters: 1000,
        target_pace_min_sec_per_km: 255,
        target_pace_max_sec_per_km: null,
      }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.code === "pace_partial")).toBe(true);
  });
});

describe("validateWorkoutBlocks — HR range e zona", () => {
  it("rejeita HR invertido", () => {
    const blocks: ValidatableBlock[] = [
      mk({
        block_type: "steady",
        duration_seconds: 600,
        target_hr_min: 170,
        target_hr_max: 140,
      }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "hr_inverted")).toBe(true);
  });

  it("rejeita target_hr_zone fora de 1..5", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "steady", duration_seconds: 600, target_hr_zone: 7 }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "hr_zone_out_of_range")).toBe(true);
  });
});

describe("validateWorkoutBlocks — estrutura repeat", () => {
  it("rejeita repeat sem repeat_count", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "repeat", repeat_count: null }),
      mk({ block_type: "interval", distance_meters: 400 }),
      mk({ block_type: "repeat_end" }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "repeat_needs_count")).toBe(true);
  });

  it("rejeita repeat_count=1", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "repeat", repeat_count: 1 }),
      mk({ block_type: "interval", distance_meters: 400 }),
      mk({ block_type: "repeat_end" }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "repeat_count_too_small")).toBe(true);
  });

  it("rejeita repeat aninhado", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "repeat", repeat_count: 3 }),
      mk({ block_type: "interval", distance_meters: 400 }),
      mk({ block_type: "repeat", repeat_count: 2 }),
      mk({ block_type: "recovery", duration_seconds: 60 }),
      mk({ block_type: "repeat_end" }),
      mk({ block_type: "repeat_end" }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "repeat_nested_unsupported")).toBe(true);
  });

  it("rejeita repeat sem repeat_end até o fim", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "repeat", repeat_count: 3 }),
      mk({ block_type: "interval", distance_meters: 400 }),
      // no repeat_end, no cooldown
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "repeat_unclosed")).toBe(true);
  });

  it("rejeita repeat_end órfão", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "steady", duration_seconds: 600 }),
      mk({ block_type: "repeat_end" }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "repeat_orphan_end")).toBe(true);
  });

  it("rejeita repeat sem bloco ativo interno", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "repeat", repeat_count: 3 }),
      mk({ block_type: "repeat_end" }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(
      result.errors.some((e) => e.code === "repeat_must_have_active_block"),
    ).toBe(true);
  });
});

describe("validateWorkoutBlocks — estimate drift", () => {
  it("drift < 30% não emite nada", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "steady", distance_meters: 5000 }),
    ];
    const result = validateWorkoutBlocks(blocks, { estimatedDistanceKm: 5.5 });
    expect(result.ok).toBe(true);
    expect(result.warnings).toEqual([]);
  });

  it("drift entre 30% e 60% emite warning (não bloqueia)", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "steady", distance_meters: 5000 }),
    ];
    // AI estimated 8km, blocks sum to 5km → drift = 37.5%
    const result = validateWorkoutBlocks(blocks, { estimatedDistanceKm: 8 });
    expect(result.ok).toBe(true);
    expect(result.warnings.length).toBeGreaterThan(0);
  });

  it("drift > 60% vira erro (provável alucinação)", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "steady", distance_meters: 5000 }),
    ];
    // AI estimated 20km, blocks sum to 5km → drift = 75%
    const result = validateWorkoutBlocks(blocks, { estimatedDistanceKm: 20 });
    expect(result.ok).toBe(false);
  });

  it("drift correto na duração aciona warning (apenas duração disponível)", () => {
    const blocks: ValidatableBlock[] = [
      mk({ block_type: "steady", duration_seconds: 1200 }),
    ];
    // Block sum = 20min, AI said 30min → drift = 33%
    const result = validateWorkoutBlocks(blocks, { estimatedDurationMinutes: 30 });
    expect(result.warnings.length).toBeGreaterThan(0);
  });
});

describe("validateWorkoutBlocks — invalid block_type", () => {
  it("rejeita block_type desconhecido", () => {
    const blocks = [
      mk({ block_type: "strides" as BlockType, duration_seconds: 60 }),
    ];
    const result = validateWorkoutBlocks(blocks);
    expect(result.errors.some((e) => e.code === "invalid_block_type")).toBe(true);
  });
});
