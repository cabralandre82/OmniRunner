/**
 * expand-repeats.ts
 *
 * Single source of truth for workout block repeat expansion and totals.
 *
 * Context — L05-21 + L05-22
 * -------------------------
 * The workout schema (`coaching_workout_blocks`) is a FLAT list of blocks
 * with optional `repeat` / `repeat_end` markers delimiting a group that
 * should be multiplied by `repeat_count`. The FIT encoder, the portal
 * summaries and the template editor all need to reason about "how many
 * steps does the watch actually run" and "what's the total distance".
 *
 * Before L05-21 there were FOUR independent implementations of this logic
 * with TWO different rules (portal used "inRepeat stays true while
 * interval|recovery", edge function used "collect until next repeat").
 * This file replaces all of them.
 *
 * The canonical rule is explicit terminators: `repeat_end` closes the
 * nearest open `repeat`. Legacy templates without terminators are handled
 * as a backward-compat fallback (matches the portal UI heuristic) and
 * emit a warning.
 *
 * Shape-agnostic generic
 * ----------------------
 * This module is used by:
 *   - Portal Server Components (reading from Supabase client).
 *   - Portal Client Components (editor preview).
 *   - Edge Function generate-fit-workout (Deno, via mirror in _shared/).
 *   - AI parser validator (before INSERT).
 *
 * Each caller has a slightly different block shape (some omit id, some
 * carry extra fields), so the helpers are generic over `B extends Block`.
 */

export type BlockType =
  | "warmup"
  | "interval"
  | "recovery"
  | "cooldown"
  | "steady"
  | "rest"
  | "repeat"
  | "repeat_end";

/** Minimal contract every block must satisfy. */
export interface Block {
  order_index: number;
  block_type: BlockType;
  duration_seconds: number | null;
  distance_meters: number | null;
  repeat_count: number | null;
}

/**
 * Expanded step as produced for display/totals.
 *
 * `multiplier` reflects how many times this block is executed in the
 * actual workout (1 outside repeats, `repeat_count` inside). It is
 * informational — the FIT encoder does NOT expand into N copies; it
 * emits ONE copy of each inner step plus a DUR_REPEAT_UNTIL_STEPS_CMPLT
 * step. See `buildRepeatPlan` for the encoder-oriented view.
 */
export interface ExpandedStep<B extends Block> {
  block: B;
  multiplier: number;
  /** Zero-based nesting depth (currently always 0 or 1). */
  depth: number;
}

export interface RepeatGroup<B extends Block> {
  openerIndex: number;
  closerIndex: number | null;
  repeatCount: number;
  innerBlocks: B[];
}

export interface ExpansionWarning {
  code:
    | "unclosed_repeat"
    | "orphan_repeat_end"
    | "nested_repeat_unsupported"
    | "empty_repeat_group"
    | "invalid_repeat_count";
  message: string;
  blockIndex: number;
}

export interface ExpansionResult<B extends Block> {
  steps: ExpandedStep<B>[];
  groups: RepeatGroup<B>[];
  warnings: ExpansionWarning[];
}

/**
 * Walk a flat block list and produce the expanded view plus warnings.
 *
 * Rules:
 *   - 'repeat' opens a group; repeat_count defaults to 1 if missing/<1.
 *   - 'repeat_end' closes the nearest open group.
 *   - A 'repeat' with no matching 'repeat_end' is closed at end-of-list
 *     (legacy fallback) with an `unclosed_repeat` warning. Inner blocks
 *     in legacy mode are those until the next 'repeat' OR a non-active
 *     block (interval|recovery is active; anything else breaks) —
 *     matches the portal UI heuristic.
 *   - 'repeat_end' without an open group yields `orphan_repeat_end` and
 *     is treated as a no-op block (not emitted as a step).
 *   - Nested repeats are rejected with `nested_repeat_unsupported` — the
 *     outer repeat stays open; the inner 'repeat' is dropped with warning.
 *   - Empty groups (no blocks between 'repeat' and 'repeat_end') emit
 *     `empty_repeat_group` and contribute no steps.
 *
 * The function is pure and deterministic. Input order is the source order
 * (ascending by order_index assumed — caller sorts).
 */
export function expandRepeats<B extends Block>(blocks: B[]): ExpansionResult<B> {
  const steps: ExpandedStep<B>[] = [];
  const groups: RepeatGroup<B>[] = [];
  const warnings: ExpansionWarning[] = [];

  let openGroup: {
    openerIndex: number;
    repeatCount: number;
    innerBlocks: B[];
  } | null = null;

  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];

    if (b.block_type === "repeat") {
      if (openGroup) {
        // Nested repeat — not supported; drop inner opener with warning.
        warnings.push({
          code: "nested_repeat_unsupported",
          message:
            "Repetições aninhadas não são suportadas. Feche o grupo externo com repeat_end antes de abrir outro.",
          blockIndex: i,
        });
        continue;
      }
      const rc = typeof b.repeat_count === "number" && b.repeat_count >= 1 ? b.repeat_count : 1;
      if (rc < 2) {
        warnings.push({
          code: "invalid_repeat_count",
          message: "repeat_count deve ser ≥ 2. Usando 1 (sem multiplicação).",
          blockIndex: i,
        });
      }
      openGroup = { openerIndex: i, repeatCount: rc, innerBlocks: [] };
      continue;
    }

    if (b.block_type === "repeat_end") {
      if (!openGroup) {
        warnings.push({
          code: "orphan_repeat_end",
          message:
            "repeat_end sem um repeat aberto precedente. Bloco ignorado.",
          blockIndex: i,
        });
        continue;
      }
      if (openGroup.innerBlocks.length === 0) {
        warnings.push({
          code: "empty_repeat_group",
          message: "Grupo repeat vazio — remova o repeat ou adicione blocos.",
          blockIndex: openGroup.openerIndex,
        });
      } else {
        for (const inner of openGroup.innerBlocks) {
          steps.push({ block: inner, multiplier: openGroup.repeatCount, depth: 1 });
        }
        groups.push({
          openerIndex: openGroup.openerIndex,
          closerIndex: i,
          repeatCount: openGroup.repeatCount,
          innerBlocks: openGroup.innerBlocks,
        });
      }
      openGroup = null;
      continue;
    }

    if (openGroup) {
      openGroup.innerBlocks.push(b);
    } else {
      steps.push({ block: b, multiplier: 1, depth: 0 });
    }
  }

  // Unclosed repeat at end of list: legacy fallback — close implicitly.
  if (openGroup) {
    warnings.push({
      code: "unclosed_repeat",
      message:
        "Grupo repeat sem repeat_end até o fim do treino. Fechamento implícito aplicado (modo legado).",
      blockIndex: openGroup.openerIndex,
    });
    if (openGroup.innerBlocks.length > 0) {
      for (const inner of openGroup.innerBlocks) {
        steps.push({ block: inner, multiplier: openGroup.repeatCount, depth: 1 });
      }
      groups.push({
        openerIndex: openGroup.openerIndex,
        closerIndex: null,
        repeatCount: openGroup.repeatCount,
        innerBlocks: openGroup.innerBlocks,
      });
    }
  }

  return { steps, groups, warnings };
}

/**
 * Aggregate distance and duration for a template, applying repeat multipliers.
 * Uses the same expansion rules as `expandRepeats`. Rest blocks contribute
 * to duration but NOT to distance (matches the pre-L05-21 portal behavior).
 */
export function sumTotals(blocks: Block[]): {
  distanceM: number;
  durationS: number;
} {
  const { steps } = expandRepeats(blocks);
  let distanceM = 0;
  let durationS = 0;

  for (const { block, multiplier } of steps) {
    const dist = block.distance_meters ?? 0;
    const dur = block.duration_seconds ?? 0;
    if (block.block_type !== "rest") {
      distanceM += dist * multiplier;
    }
    durationS += dur * multiplier;
  }

  return { distanceM, durationS };
}

/**
 * Encoder-oriented plan: one entry per block (no N-copy expansion), marking
 * which entries are inside a repeat group and where the DUR_REPEAT_UNTIL_
 * STEPS_CMPLT marker should point.
 *
 * Consumed by the FIT encoder in `generate-fit-workout/index.ts` (via the
 * mirror in `supabase/functions/_shared/workout_expand.ts`).
 *
 * Output shape:
 *   [
 *     { kind: "step", block: warmup },
 *     { kind: "step", block: interval, inRepeat: { startStepIndex: 1, count: 5 } },
 *     { kind: "step", block: recovery, inRepeat: { startStepIndex: 1, count: 5 } },
 *     { kind: "repeat_marker", targetStepIndex: 1, count: 5 },
 *     { kind: "step", block: cooldown },
 *   ]
 */
export type EncoderEntry<B extends Block> =
  | { kind: "step"; block: B; inRepeatGroupStart: number | null; repeatCount: number }
  | { kind: "repeat_marker"; targetStepIndex: number; count: number };

export function buildEncoderPlan<B extends Block>(blocks: B[]): {
  entries: EncoderEntry<B>[];
  warnings: ExpansionWarning[];
} {
  const { groups, warnings } = expandRepeats(blocks);
  const entries: EncoderEntry<B>[] = [];
  let stepIndex = 0;

  // Index groups by the (pre-sort) array position of their opener for O(1) lookup.
  const groupByOpener = new Map<number, RepeatGroup<B>>();
  for (const g of groups) {
    groupByOpener.set(g.openerIndex, g);
  }
  const closerByOpener = new Map<number, number | null>();
  for (const g of groups) {
    closerByOpener.set(g.openerIndex, g.closerIndex);
  }

  let activeGroup: { opener: number; startStep: number; count: number } | null = null;

  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];

    if (b.block_type === "repeat") {
      const g = groupByOpener.get(i);
      if (!g) continue; // dropped by warnings (nested/empty)
      activeGroup = { opener: i, startStep: stepIndex, count: g.repeatCount };
      continue;
    }

    if (b.block_type === "repeat_end") {
      if (activeGroup) {
        entries.push({
          kind: "repeat_marker",
          targetStepIndex: activeGroup.startStep,
          count: activeGroup.count,
        });
        // The repeat marker itself IS a FIT step (message_index counter).
        stepIndex++;
        activeGroup = null;
      }
      continue;
    }

    entries.push({
      kind: "step",
      block: b,
      inRepeatGroupStart: activeGroup ? activeGroup.startStep : null,
      repeatCount: activeGroup ? activeGroup.count : 1,
    });
    stepIndex++;
  }

  // Legacy: unclosed repeat at end-of-list → emit closing marker.
  if (activeGroup) {
    entries.push({
      kind: "repeat_marker",
      targetStepIndex: activeGroup.startStep,
      count: activeGroup.count,
    });
  }

  return { entries, warnings };
}
