import { describe, it, expect } from "vitest";
import {
  type Block,
  expandRepeats,
  sumTotals,
  buildEncoderPlan,
} from "./expand-repeats";

// ─── Helpers ──────────────────────────────────────────────────────────────────

let seq = 0;
function b(partial: Partial<Block>): Block {
  return {
    order_index: seq++,
    block_type: partial.block_type ?? "steady",
    duration_seconds: partial.duration_seconds ?? null,
    distance_meters: partial.distance_meters ?? null,
    repeat_count: partial.repeat_count ?? null,
  };
}
function reset() {
  seq = 0;
}

// ─── expandRepeats ────────────────────────────────────────────────────────────

describe("expandRepeats — L05-21 canonical cases", () => {
  it("simple workout without repeats expands 1:1", () => {
    reset();
    const blocks = [
      b({ block_type: "warmup", duration_seconds: 600 }),
      b({ block_type: "steady", distance_meters: 5000 }),
      b({ block_type: "cooldown", duration_seconds: 300 }),
    ];
    const { steps, groups, warnings } = expandRepeats(blocks);
    expect(steps).toHaveLength(3);
    expect(steps.every((s) => s.multiplier === 1)).toBe(true);
    expect(steps.every((s) => s.depth === 0)).toBe(true);
    expect(groups).toHaveLength(0);
    expect(warnings).toHaveLength(0);
  });

  it("intervalado canônico com cooldown fora do loop (BUG #1 REGRESSÃO)", () => {
    reset();
    // Exact shape that corrupted the FIT before L05-21: warmup + 5×(int+rec) + cooldown.
    const blocks = [
      b({ block_type: "warmup", duration_seconds: 600 }),
      b({ block_type: "repeat", repeat_count: 5 }),
      b({ block_type: "interval", distance_meters: 1000 }),
      b({ block_type: "recovery", duration_seconds: 120 }),
      b({ block_type: "repeat_end" }),
      b({ block_type: "cooldown", duration_seconds: 600 }),
    ];
    const { steps, groups, warnings } = expandRepeats(blocks);

    expect(warnings).toEqual([]);
    expect(groups).toHaveLength(1);
    expect(groups[0].repeatCount).toBe(5);
    expect(groups[0].innerBlocks.map((x) => x.block_type)).toEqual([
      "interval",
      "recovery",
    ]);

    // Steps should be: warmup (×1) + interval (×5) + recovery (×5) + cooldown (×1)
    expect(steps).toHaveLength(4);
    expect(steps[0].block.block_type).toBe("warmup");
    expect(steps[0].multiplier).toBe(1);
    expect(steps[1].block.block_type).toBe("interval");
    expect(steps[1].multiplier).toBe(5);
    expect(steps[2].block.block_type).toBe("recovery");
    expect(steps[2].multiplier).toBe(5);
    expect(steps[3].block.block_type).toBe("cooldown");
    expect(steps[3].multiplier).toBe(1); // NOT 5! This is the bug that L05-21 fixes.
  });

  it("múltiplos grupos repeat em sequência", () => {
    reset();
    const blocks = [
      b({ block_type: "warmup", duration_seconds: 600 }),
      b({ block_type: "repeat", repeat_count: 3 }),
      b({ block_type: "interval", distance_meters: 400 }),
      b({ block_type: "recovery", duration_seconds: 60 }),
      b({ block_type: "repeat_end" }),
      b({ block_type: "rest", duration_seconds: 180 }),
      b({ block_type: "repeat", repeat_count: 2 }),
      b({ block_type: "interval", distance_meters: 800 }),
      b({ block_type: "recovery", duration_seconds: 120 }),
      b({ block_type: "repeat_end" }),
      b({ block_type: "cooldown", duration_seconds: 600 }),
    ];
    const { steps, groups, warnings } = expandRepeats(blocks);

    expect(warnings).toEqual([]);
    expect(groups).toHaveLength(2);
    expect(groups[0].repeatCount).toBe(3);
    expect(groups[1].repeatCount).toBe(2);

    // warmup + 3×int + 3×rec + rest + 2×int + 2×rec + cooldown = 7 steps
    expect(steps.map((s) => [s.block.block_type, s.multiplier])).toEqual([
      ["warmup", 1],
      ["interval", 3],
      ["recovery", 3],
      ["rest", 1],
      ["interval", 2],
      ["recovery", 2],
      ["cooldown", 1],
    ]);
  });

  it("nested repeat é rejeitado com warning e outer permanece", () => {
    reset();
    const blocks = [
      b({ block_type: "repeat", repeat_count: 3 }),
      b({ block_type: "interval", distance_meters: 400 }),
      b({ block_type: "repeat", repeat_count: 2 }), // nested — not supported
      b({ block_type: "recovery", duration_seconds: 60 }),
      b({ block_type: "repeat_end" }),
    ];
    const { steps, groups, warnings } = expandRepeats(blocks);

    expect(warnings.some((w) => w.code === "nested_repeat_unsupported")).toBe(true);
    // Inner opener dropped; outer still closes correctly with 2 inner blocks.
    expect(groups).toHaveLength(1);
    expect(groups[0].repeatCount).toBe(3);
    expect(steps.map((s) => s.block.block_type)).toEqual(["interval", "recovery"]);
  });

  it("orphan repeat_end é ignorado com warning", () => {
    reset();
    const blocks = [
      b({ block_type: "steady", distance_meters: 3000 }),
      b({ block_type: "repeat_end" }), // no opener before it
      b({ block_type: "cooldown", duration_seconds: 300 }),
    ];
    const { steps, warnings } = expandRepeats(blocks);
    expect(warnings.some((w) => w.code === "orphan_repeat_end")).toBe(true);
    expect(steps.map((s) => s.block.block_type)).toEqual(["steady", "cooldown"]);
  });

  it("repeat vazio emite warning e não contribui com steps", () => {
    reset();
    const blocks = [
      b({ block_type: "warmup", duration_seconds: 300 }),
      b({ block_type: "repeat", repeat_count: 5 }),
      b({ block_type: "repeat_end" }),
      b({ block_type: "cooldown", duration_seconds: 300 }),
    ];
    const { steps, groups, warnings } = expandRepeats(blocks);
    expect(warnings.some((w) => w.code === "empty_repeat_group")).toBe(true);
    expect(groups).toHaveLength(0);
    expect(steps.map((s) => s.block.block_type)).toEqual(["warmup", "cooldown"]);
  });

  it("unclosed repeat no fim da lista usa fallback legado com warning", () => {
    reset();
    const blocks = [
      b({ block_type: "warmup", duration_seconds: 600 }),
      b({ block_type: "repeat", repeat_count: 4 }),
      b({ block_type: "interval", distance_meters: 400 }),
      b({ block_type: "recovery", duration_seconds: 60 }),
      // NO repeat_end, NO cooldown → legacy fallback closes implicitly
    ];
    const { steps, groups, warnings } = expandRepeats(blocks);
    expect(warnings.some((w) => w.code === "unclosed_repeat")).toBe(true);
    expect(groups).toHaveLength(1);
    expect(groups[0].closerIndex).toBeNull();
    expect(steps.map((s) => [s.block.block_type, s.multiplier])).toEqual([
      ["warmup", 1],
      ["interval", 4],
      ["recovery", 4],
    ]);
  });

  it("repeat_count < 2 emite warning mas não quebra", () => {
    reset();
    const blocks = [
      b({ block_type: "repeat", repeat_count: 1 }),
      b({ block_type: "interval", distance_meters: 400 }),
      b({ block_type: "repeat_end" }),
    ];
    const { steps, warnings } = expandRepeats(blocks);
    expect(warnings.some((w) => w.code === "invalid_repeat_count")).toBe(true);
    expect(steps).toHaveLength(1);
    expect(steps[0].multiplier).toBe(1);
  });
});

// ─── sumTotals ────────────────────────────────────────────────────────────────

describe("sumTotals — respeita multiplicador e exclui rest da distância", () => {
  it("intervalado: 10min warmup + 5×(1km + 2min) + 10min cooldown", () => {
    reset();
    const blocks = [
      b({ block_type: "warmup", duration_seconds: 600 }),
      b({ block_type: "repeat", repeat_count: 5 }),
      b({ block_type: "interval", distance_meters: 1000 }),
      b({ block_type: "recovery", duration_seconds: 120 }),
      b({ block_type: "repeat_end" }),
      b({ block_type: "cooldown", duration_seconds: 600 }),
    ];
    const { distanceM, durationS } = sumTotals(blocks);
    // distance: 5 × 1000 = 5000 (warmup/cooldown/recovery have no distance set)
    expect(distanceM).toBe(5000);
    // duration: 600 + 5×0 (interval has no duration) + 5×120 + 600 = 1800
    expect(durationS).toBe(600 + 5 * 120 + 600);
  });

  it("rest blocks não contam para distância, mas contam para duração", () => {
    reset();
    const blocks = [
      b({ block_type: "rest", duration_seconds: 300, distance_meters: 500 }),
      b({ block_type: "steady", distance_meters: 2000, duration_seconds: 600 }),
    ];
    const { distanceM, durationS } = sumTotals(blocks);
    expect(distanceM).toBe(2000); // rest distance excluded
    expect(durationS).toBe(900);
  });
});

// ─── buildEncoderPlan ─────────────────────────────────────────────────────────

describe("buildEncoderPlan — shape para FIT encoder", () => {
  it("emite repeat_marker apontando para o step inicial do grupo", () => {
    reset();
    const blocks = [
      b({ block_type: "warmup", duration_seconds: 600 }),
      b({ block_type: "repeat", repeat_count: 5 }),
      b({ block_type: "interval", distance_meters: 1000 }),
      b({ block_type: "recovery", duration_seconds: 120 }),
      b({ block_type: "repeat_end" }),
      b({ block_type: "cooldown", duration_seconds: 600 }),
    ];
    const { entries, warnings } = buildEncoderPlan(blocks);
    expect(warnings).toEqual([]);

    // Expected FIT step layout:
    //   0: warmup (step)
    //   1: interval (step, in group starting at 1)
    //   2: recovery (step, in group starting at 1)
    //   3: repeat_marker → target=1, count=5
    //   4: cooldown (step)
    expect(entries).toHaveLength(5);
    expect(entries[0]).toMatchObject({ kind: "step", inRepeatGroupStart: null });
    expect(entries[1]).toMatchObject({ kind: "step", inRepeatGroupStart: 1, repeatCount: 5 });
    expect(entries[2]).toMatchObject({ kind: "step", inRepeatGroupStart: 1, repeatCount: 5 });
    expect(entries[3]).toMatchObject({ kind: "repeat_marker", targetStepIndex: 1, count: 5 });
    expect(entries[4]).toMatchObject({ kind: "step", inRepeatGroupStart: null });
    expect((entries[4] as { kind: string; block: Block }).block.block_type).toBe("cooldown");
  });

  it("legacy unclosed repeat recebe repeat_marker sintético no fim", () => {
    reset();
    const blocks = [
      b({ block_type: "repeat", repeat_count: 3 }),
      b({ block_type: "interval", distance_meters: 400 }),
    ];
    const { entries, warnings } = buildEncoderPlan(blocks);
    expect(warnings.some((w) => w.code === "unclosed_repeat")).toBe(true);
    expect(entries).toHaveLength(2);
    expect(entries[1]).toMatchObject({ kind: "repeat_marker", targetStepIndex: 0, count: 3 });
  });

  it("dois grupos não colidem — cada marker aponta pro próprio start", () => {
    reset();
    const blocks = [
      b({ block_type: "repeat", repeat_count: 3 }),
      b({ block_type: "interval", distance_meters: 400 }),
      b({ block_type: "repeat_end" }),
      b({ block_type: "repeat", repeat_count: 2 }),
      b({ block_type: "interval", distance_meters: 800 }),
      b({ block_type: "repeat_end" }),
    ];
    const { entries } = buildEncoderPlan(blocks);
    // Layout:
    //   0: interval (group A, start=0, count=3)
    //   1: repeat_marker → 0, count=3
    //   2: interval (group B, start=2, count=2)
    //   3: repeat_marker → 2, count=2
    expect(entries).toHaveLength(4);
    expect(entries[1]).toMatchObject({ kind: "repeat_marker", targetStepIndex: 0, count: 3 });
    expect(entries[3]).toMatchObject({ kind: "repeat_marker", targetStepIndex: 2, count: 2 });
  });
});
