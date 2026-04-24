---
id: L05-28
audit_ref: "5.28"
lens: 5
title: "Rest/Recovery: semântica 'parado/caminhando/trote' não representada"
severity: medium
status: fix-pending
wave: 0
discovered_at: 2026-04-24
fixed_at: null
closed_at: null
tags: ["workout", "semantics", "coach", "fit-export", "ai-parser", "rest-mode"]
files:
  - supabase/migrations/20260424150000_l05_28_rest_mode.sql
  - portal/src/lib/workout/validate.ts
  - portal/src/lib/workout/validate.test.ts
  - portal/src/app/api/training-plan/ai/parse-workout/route.ts
  - portal/src/app/api/training-plan/ai/parse-workout/route.test.ts
  - portal/src/app/api/training-plan/week-templates/[templateId]/workouts/route.ts
  - portal/src/app/api/training-plan/week-templates/[templateId]/workouts/[workoutId]/route.ts
  - portal/src/app/api/training-plan/weeks/[weekId]/workouts/route.ts
  - portal/src/app/api/training-plan/workouts/[workoutId]/update/route.ts
  - portal/src/app/api/workouts/templates/route.ts
  - portal/src/app/(portal)/workouts/[id]/page.tsx
  - portal/src/app/(portal)/workouts/[id]/edit/page.tsx
  - portal/src/app/(portal)/workouts/template-builder.tsx
  - omni_runner/lib/domain/entities/plan_workout_entity.dart
correction_type: code
test_required: true
tests:
  - portal/src/lib/workout/validate.test.ts
  - portal/src/app/api/training-plan/ai/parse-workout/route.test.ts
linked_issues: []
linked_prs: []
owner: platform-workout
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-28] Rest/Recovery: semântica 'parado/caminhando/trote' não representada

> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 0 · **Status:** fix-pending

**Camada:** DB schema + AI parser + Portal UI + Flutter
**Personas impactadas:** atleta amador (lê "Descanso 2min" no relógio e não sabe se é pra parar, caminhar ou trotar), coach (escreve "2min trote" na descrição e perde a instrução no .fit), AI parser (precisa decidir entre `rest` e `recovery` sem granularidade real)

## Achado

O schema atual de `coaching_workout_blocks` tem apenas dois tipos para
representar pausas entre esforços:

- `block_type='rest'` — "descanso" (mapeia para INTENSITY_REST no FIT:
  o relógio mostra "REST" e pausa distância/pace; assume atleta
  parado/andando lento).
- `block_type='recovery'` — "recuperação ativa" (INTENSITY_RECOVERY:
  o relógio continua gravando; assume trote leve Z1-Z2).

O problema: o mundo real dos coaches e atletas tem **três** modos, não
dois:

1. **Parado** (stand_still): atleta para, bebe água, respira. Comum em
   treinos de velocidade máxima e testes.
2. **Caminhando** (walk): atleta caminha ativamente entre séries. É o
   modo mais comum em treinos de masters, pós-cirúrgicos, retorno de
   lesão — e em quase todo intervalado longo (Yasso 800s, por exemplo).
3. **Trotando** (jog): atleta mantém trote leve sem parar. Típico de
   intervalados de resistência e fartleks.

Hoje:

- "2min pausa" → AI gera `rest` → relógio mostra "REST" genérico.
  Atleta não sabe se pode parar ou se tem que manter movimento.
- "2min trote leve" → AI gera `recovery` → ok, mas indistinguível de
  "2min caminhada leve" (que também cai em `recovery`).
- "2min caminhando" → AI ou vira `rest` (zera a recuperação ativa) ou
  vira `recovery` com zona baixa (nunca deixa claro ao atleta que é pra
  andar, não trotar).

**Impacto no atleta:** recebe uma instrução ambígua no relógio.
Se interpretar errado (ex: atleta masters trotando num treino em que o
coach queria caminhada ativa) pode fazer diferença real na resposta
adaptativa da sessão.

**Impacto no coach:** perde a especificidade da instrução que escreveu
em português no campo texto. O .fit chega no Garmin do atleta como um
REST/RECOVERY genérico, sem a anotação.

**Impacto no AI parser:** hoje ele escolhe arbitrariamente entre
`rest` e `recovery` quando o texto é ambíguo, sem sinalizar que houve
perda semântica.

## Impacto

- Retenção: atleta iniciante confuso no primeiro intervalado aceita
  "Descanso 2min" e fica parado quando o coach queria caminhada. Ao
  reportar "não consegui manter o pace no tiro 4", o coach não tem
  como explicar "é porque você parou em vez de caminhar". Fricção que
  escala com % de iniciantes.
- Qualidade de dados: telemetria de "tempo médio em zona Z1 durante
  recovery blocks" vira inútil quando metade dos recovery blocks são
  caminhada (esperado Z1 baixo) e metade são trote (esperado Z1 alto).
- Futuro (L05-R-04): quando expormos recomendações automáticas de
  ajuste de treino, o modelo precisa do rest_mode pra entender por
  que o HR do atleta ficou em 110 no recovery em vez de 130.

Medium porque não quebra funcionalidade existente — os dois modos
atuais continuam funcionando — mas fecha um gap semântico que já
está custando clareza para o atleta hoje e vai piorar à medida que
escalam os usuários sem passar pelo coach durante a sessão.

## Correção proposta

### 1. DB: coluna `rest_mode` + CHECK + constraint trigger

Migration `20260424150000_l05_28_rest_mode.sql`:

```sql
ALTER TABLE public.coaching_workout_blocks
  ADD COLUMN rest_mode text
  CHECK (rest_mode IN ('stand_still', 'walk', 'jog'));

-- rest_mode só é válido para block_type em (rest, recovery).
-- Enforcement via CHECK composto (referenciando outra coluna na mesma
-- linha).
ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT coaching_workout_blocks_rest_mode_scope
  CHECK (
    rest_mode IS NULL
    OR block_type IN ('rest', 'recovery')
  );
```

Valores:

| block_type | rest_mode     | UI label                  | encoder intensity |
|------------|---------------|---------------------------|-------------------|
| rest       | NULL (legacy) | "Descanso"                | INTENSITY_REST    |
| rest       | stand_still   | "Descanso (parado)"       | INTENSITY_REST    |
| rest       | walk          | "Descanso (caminhando)"   | INTENSITY_REST    |
| recovery   | NULL (legacy) | "Recuperação"             | INTENSITY_RECOVERY|
| recovery   | walk          | "Recuperação (caminhando)"| INTENSITY_RECOVERY|
| recovery   | jog           | "Recuperação (trote)"     | INTENSITY_RECOVERY|

Nota: `jog` é inválido pra `rest` (definition-level: rest significa
NÃO trotar; quem quer trotar usa `recovery`). Enforcement: a UI não
oferece "trote" como opção dentro do block_type=rest.

Encoder FIT NÃO muda — o relógio não tem detecção física pra
distinguir "parado" de "caminhando", então a intensidade FIT continua
sendo determinada apenas pelo block_type. O rest_mode é metadata
semântica pra UI + AI copilot + análise posterior.

### 2. validate.ts — nova invariante

`rest_mode_misplaced`: erro quando `rest_mode != null` e
`block_type NOT IN ('rest', 'recovery')`. Mirror do CHECK do DB
com mensagem amigável em português.

`rest_mode_invalid_for_type`: erro quando `block_type='rest'` e
`rest_mode='jog'` (jog só em recovery).

### 3. AI parser — prompt + sanitização

Prompt:

> Para blocos de descanso/recuperação, identifique o modo:
> - "parado", "pausa total", "respire" → rest_mode: "stand_still"
> - "caminhando", "caminhada", "andando" → rest_mode: "walk"
> - "trote leve", "trote", "jog" → rest_mode: "jog" (exige
>   block_type=recovery, nunca rest)
> Se ambíguo, deixe rest_mode como null.

Sanitização: `validRestModes = ["stand_still", "walk", "jog"]`; se
AI devolver outro valor, vira null (não falhamos o request pra isso
— rest_mode é best-effort).

### 4. Zod schemas — 5 endpoints + templates

Os 5 schemas que atualmente definem `block_type` enum ganham
`rest_mode: z.enum([...]).nullable().optional()`.

### 5. Portal UI — sufixo no label

`workouts/[id]/page.tsx` e `template-builder.tsx`:
`BLOCK_TYPE_LABELS[block.block_type]` + sufixo " (parado|caminhando|
trote)" quando rest_mode presente.

Template builder ganha um select rest_mode no AddBlockForm (visível
só quando block_type ∈ {rest, recovery}).

### 6. Flutter — entity + label

`PlanWorkoutBlock` ganha `restMode: String?` no construtor e no
fromJson. `blockTypeLabel` passa a incluir o sufixo quando restMode
presente. Athlete_workout_detail_screen passa a renderizar o label
enriquecido automaticamente (já usa blockTypeLabel).

## Teste de regressão

Unitários (validate.test.ts):
- `rest` + `rest_mode='stand_still'` ok
- `rest` + `rest_mode='walk'` ok
- `rest` + `rest_mode='jog'` erro (rest_mode_invalid_for_type)
- `recovery` + `rest_mode='jog'` ok
- `interval` + `rest_mode='walk'` erro (rest_mode_misplaced)
- `warmup` + `rest_mode=null` ok

Unitários (parse-workout/route.test.ts):
- AI retorna `rest` + `rest_mode='walk'` → aceita, preserva no output.
- AI retorna `rest` + `rest_mode='foobar'` → normaliza para null
  (warning, não erro — rest_mode é best-effort).

Manual:
- Coach cria template com bloco "Descanso (caminhando) 2min" →
  aparece corretamente no portal e no .fit (como REST intensity).
- Atleta abre app → vê "Descanso (caminhando)" no detalhe do treino.
- AI parser: "4x400m com 1min pausa parado" → produz rest blocks
  com rest_mode='stand_still'.

## Cross-refs

- L05-21 (fixed) — repeat_end terminator.
- L05-22 (fixed) — UI/encoder heuristic divergence.
- L05-23 (fixed) — AI parser strict block_type.
- L05-26 (fixed) — export log (rest_mode não é logado por export,
  vai no snapshot do treino).

## Histórico

- `2026-04-24` — Descoberto durante Wave B slice 4, ao revisitar o
  gap semântico identificado no estudo inicial de passagem de treino
  ("rest.mode passive/active").
