/**
 * workout_expand.ts — Deno mirror of portal/src/lib/workout/expand-repeats.ts
 *
 * Kept in sync manually. Any change HERE must be mirrored in the portal file
 * and vice-versa. The parity is enforced by `portal/src/lib/workout/expand-repeats.parity.test.ts`.
 *
 * See L05-21 and L05-22 in docs/audit/findings/ for the full context.
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

export interface Block {
  order_index: number;
  block_type: BlockType;
  duration_seconds: number | null;
  distance_meters: number | null;
  repeat_count: number | null;
}

export interface ExpandedStep<B extends Block> {
  block: B;
  multiplier: number;
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
          message: "repeat_end sem um repeat aberto precedente. Bloco ignorado.",
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

  const groupByOpener = new Map<number, RepeatGroup<B>>();
  for (const g of groups) {
    groupByOpener.set(g.openerIndex, g);
  }

  let activeGroup: { opener: number; startStep: number; count: number } | null = null;

  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];

    if (b.block_type === "repeat") {
      const g = groupByOpener.get(i);
      if (!g) continue;
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

  if (activeGroup) {
    entries.push({
      kind: "repeat_marker",
      targetStepIndex: activeGroup.startStep,
      count: activeGroup.count,
    });
  }

  return { entries, warnings };
}
