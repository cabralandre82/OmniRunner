---
id: L05-21
audit_ref: "5.21"
lens: 5
title: "Workout: bloco repeat sem terminador corrompe passagem para .FIT"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-24
tags: ["workout", "fit-export", "watch", "coach", "go-to-market"]
files:
  - supabase/migrations/20260424130000_l05_21_workout_repeat_terminator.sql
  - supabase/functions/_shared/workout_expand.ts
  - supabase/functions/generate-fit-workout/index.ts
  - portal/src/lib/workout/expand-repeats.ts
  - portal/src/lib/workout/expand-repeats.test.ts
  - portal/src/app/(portal)/workouts/page.tsx
  - portal/src/app/(portal)/workouts/[id]/page.tsx
  - portal/src/app/(portal)/workouts/template-builder.tsx
  - tools/test_fit_generation.js
correction_type: migration
test_required: true
tests:
  - portal/src/lib/workout/expand-repeats.test.ts
  - tools/test_fit_generation.js
linked_issues: []
linked_prs: []
owner: platform-workout
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-21] Workout: bloco repeat sem terminador corrompe passagem para .FIT

> **Lente:** 5 — CPO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending

**Camada:** schema SQL + Edge Function Deno + Portal Next.js + App Flutter
**Personas impactadas:** coach (prescreve errado sem saber), atleta (roda treino errado no relógio)

## Achado

O schema `coaching_workout_blocks` modela repetições como uma **lista flat com marker** — um bloco `block_type='repeat'` com `repeat_count=N` indica que os blocos seguintes devem ser repetidos N vezes. O problema é que **não existe um terminador explícito** para o grupo de repetição.

Isso criou duas convenções divergentes no código:

1. **Edge Function `generate-fit-workout`** (`supabase/functions/generate-fit-workout/index.ts:285-295`): coleta todos os blocos após o `repeat` até encontrar **outro** `repeat` ou o fim da lista:

```285:295:supabase/functions/generate-fit-workout/index.ts
    if (block.block_type === "repeat") {
      const repeatCount = block.repeat_count ?? 1;
      const repeatStartIndex = steps.length;

      // Collect inner blocks (everything between repeat and next repeat/end)
      i++;
      const innerBlocks: WorkoutBlock[] = [];
      while (i < blocks.length && blocks[i].block_type !== "repeat") {
        innerBlocks.push(blocks[i]);
        i++;
      }
```

2. **Portal UI** (`workouts/page.tsx:38`, `[id]/page.tsx:192`, `template-builder.tsx:270`): heurística diferente — `inRepeat` permanece true apenas enquanto o `block_type` for `interval` ou `recovery`:

```30:42:portal/src/app/(portal)/workouts/page.tsx
  for (const b of blocks) {
    if (b.block_type === "repeat") {
      repeatMult = b.repeat_count ?? 1;
      inRepeat = true;
      continue;
    }
    if (b.block_type !== "rest" && b.distance_meters) {
      total += b.distance_meters * (inRepeat ? repeatMult : 1);
    }
    if (!["interval", "recovery"].includes(b.block_type)) {
      inRepeat = false;
      repeatMult = 1;
    }
  }
```

## Impacto

**Cenário real** — coach prescreve `[warmup 10min, repeat(5), interval 1km, recovery 2min, cooldown 10min]`:

| Camada | O que é interpretado | O que o atleta vê |
|---|---|---|
| Portal UI (lista) | `warmup → 5×(interval+recovery) → cooldown` | Correto |
| Portal UI (total) | 5km intervalo + 2min×5 rec + 10min cooldown | Correto |
| Relógio Garmin (após .fit) | `warmup → 5×(interval+recovery+cooldown) → END` | **ERRADO** — 5 "cooldowns" dentro do loop, nenhum final |

O atleta no Garmin FR265 executa um treino **fundamentalmente diferente** do prescrito: 5 rodadas com "cooldown" de 10min intercaladas entre intervalos, sem recuperação ativa clara, sem cooldown final. Pace targets ficam aplicados a blocos que não deveriam tê-los. Distance goal vai para `~55km` em vez dos `~15km` prescritos.

**Consequências de negócio:**
- Primeiro coach que enviar um intervalado completo perde a confiança — a prescrição não chega fielmente.
- Atleta machucado (excesso de volume/intensidade) é passivo legal real.
- Palavra na comunidade: "o app do Omni manda errado para o relógio" — morte silenciosa do produto.

**Por que não foi detectado antes:**
- `tools/validate_fit.js` valida **CRC-16 e estrutura de mensagens FIT**, não semântica de prescrição.
- `tools/test_fit_generation.js:295-302` usa exatamente o workout-bug-trigger (`[warmup, repeat(5), interval, recovery, steady, cooldown]`) e passa na self-validation — ele testa "o .fit é parseável", não "o .fit representa o treino original".
- Testes do portal e do AI parser validam o objeto JSON retornado, não a cadeia completa até o encoder.

## Correção proposta

1. **Migration** — adicionar `'repeat_end'` ao CHECK de `block_type`:
   ```sql
   ALTER TABLE public.coaching_workout_blocks
     DROP CONSTRAINT IF EXISTS coaching_workout_blocks_block_type_check;
   ALTER TABLE public.coaching_workout_blocks
     ADD CONSTRAINT coaching_workout_blocks_block_type_check
     CHECK (block_type IN ('warmup','interval','recovery','cooldown','steady','rest','repeat','repeat_end'));
   ```
   Backfill: para cada template que tenha `repeat` seguido por bloco não-`interval`/`recovery`, inserir um `repeat_end` no gap, bumpando `order_index` dos subsequentes.

2. **Módulo compartilhado** `supabase/functions/_shared/workout_expand.ts` + mirror em `portal/src/lib/workout/expand-repeats.ts` — função única `expandRepeats(blocks)` que respeita o terminador.

3. **Edge Function** `generate-fit-workout`: substituir loop inline pelo módulo compartilhado.

4. **Portal UI** — 3 arquivos: substituir heurística `["interval","recovery"]` pela lógica unificada via helper TS do portal.

5. **Zod schemas** das 5 rotas API (`week-templates/.../workouts`, `weeks/.../workouts`, `workouts/[id]/update`): adicionar `"repeat_end"` ao enum.

6. **AI parser** (`parse-workout/route.ts`): atualizar system prompt para o GPT-4o emitir `repeat_end` corretamente, e adicionar ao `validBlockTypes`.

## Teste de regressão

Testes golden em `tools/test_fit_generation.js` + `supabase/functions/generate-fit-workout/expand.test.ts` (nova) cobrindo:

- Intervalado clássico: `[warmup, repeat(5), interval, recovery, repeat_end, cooldown]` → 5 steps FIT ativos + 1 step repeat_until + 1 cooldown fora do loop.
- Múltiplos grupos: `[warmup, repeat(3), int_A, rec_A, repeat_end, rest, repeat(3), int_B, rec_B, repeat_end, cooldown]`.
- Edge cases: `repeat` no fim sem `repeat_end` (aceitar como legado implícito até fim-da-lista, warn).
- Repeat vazio (sem steps entre `repeat` e `repeat_end`) — rejeitar com erro claro.

## Cross-refs

- L05-22 (sibling): heurística divergente `inRepeat` entre UI e encoder — fix conjunto.
- L05-23 (sibling): AI parser aceita block_type inválido silenciosamente.
- L21-07 (wont-fix): interop FIT inbound via Strava-único; este finding é **outbound** (app→relógio), ortogonal.
- L22-10 (fixed-docs): Apple Watch/Wear OS nativo — alternativa para quem não aceita `.fit`.

## Histórico

- `2026-04-24` — Descoberto durante vistoria de passagem de treino ("Workout Passing Audit 100/100"), validando proposta de schema estruturado de outra IA.
