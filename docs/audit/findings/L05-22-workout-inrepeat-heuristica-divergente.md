---
id: L05-22
audit_ref: "5.22"
lens: 5
title: "Workout: heurística inRepeat divergente entre portal UI e FIT encoder"
severity: high
status: fixed
wave: 0
discovered_at: 2026-04-24
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["workout", "fit-export", "consistency", "coach"]
files:
  - portal/src/lib/workout/expand-repeats.ts
  - portal/src/lib/workout/expand-repeats.test.ts
  - supabase/functions/_shared/workout_expand.ts
  - portal/src/app/(portal)/workouts/page.tsx
  - portal/src/app/(portal)/workouts/[id]/page.tsx
  - portal/src/app/(portal)/workouts/template-builder.tsx
  - supabase/functions/generate-fit-workout/index.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/workout/expand-repeats.test.ts
linked_issues: []
linked_prs:
  - f49e1c6
owner: platform-workout
runbook: null
effort_points: 3
blocked_by:
  - L05-21
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-22] Workout: heurística inRepeat divergente entre portal UI e FIT encoder

> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 0 · **Status:** fix-pending

**Camada:** Portal Next.js + Edge Function Deno
**Personas impactadas:** coach (vê uma coisa no portal, atleta recebe outra no relógio)

## Achado

Existem **quatro cópias independentes** da lógica de expansão de repetições, com **duas regras diferentes** entre elas:

- **Portal (3 arquivos)** — `workouts/page.tsx:30-42`, `workouts/[id]/page.tsx:187-195`, `workouts/template-builder.tsx:265-273`:
  ```
  inRepeat = true quando block_type === "repeat"
  inRepeat = false quando block_type NOT IN ("interval","recovery")  ← regra heurística
  ```

- **Edge Function** — `generate-fit-workout/index.ts:292`:
  ```
  Collect blocks until next "repeat" or end-of-list  ← regra diferente
  ```

## Impacto

Coach edita template no portal, vê preview "total 5km". Atleta abre no app, pressiona "Enviar para relógio", o `.fit` encoder produz algo diferente do preview. Confiança perdida.

Mesmo com L05-21 resolvido (repeat_end introduzido), se as 4 cópias não forem consolidadas, qualquer divergência futura volta a reaparecer.

## Correção proposta

1. Criar `portal/src/lib/workout/expand-repeats.ts` com função única:
   ```ts
   export function expandRepeats<B extends Block>(blocks: B[]): ExpandedStep<B>[];
   export function sumTotals(blocks: Block[]): { distanceM: number; durationS: number };
   ```

2. Criar mirror em `supabase/functions/_shared/workout_expand.ts` (Deno não importa TS arbitrário do portal).

3. Substituir:
   - `workouts/page.tsx` → usar `sumTotals` + `expandRepeats`.
   - `workouts/[id]/page.tsx` → idem.
   - `workouts/template-builder.tsx` → idem.
   - `generate-fit-workout/index.ts:278-319` → substituir `expandBlocks` por import do shared.

4. Testes unitários em `portal/src/lib/workout/expand-repeats.test.ts` cobrindo 8 cenários canônicos.

## Teste de regressão

Teste paridade: roda o mesmo `blocks[]` pelo helper Deno e pelo helper TS, assert que as listas expandidas são idênticas (mesmo número de steps, mesma ordem, mesmos flags). Rodar em CI.

## Cross-refs

- **Bloqueado por** L05-21 — o terminador precisa existir primeiro para as 4 cópias convergirem numa única regra correta.

## Histórico

- `2026-04-24` — Descoberto durante vistoria de passagem de treino.
