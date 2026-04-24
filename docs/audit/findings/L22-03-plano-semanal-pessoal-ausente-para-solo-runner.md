---
id: L22-03
audit_ref: "22.3"
lens: 22
title: "Plano semanal pessoal ausente para solo runner"
severity: critical
status: wont-fix
wave: 1
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["scope-mismatch", "personas", "athlete-amateur", "coach-driven"]
files:
  - supabase/migrations/20260407000000_training_plan_module.sql
  - portal/src/lib/periodization/types.ts
  - portal/src/lib/periodization/generate-periodization.ts
correction_type: none
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Finding resolvido como **scope-mismatch / N/A**. A hipótese do finding
  original era "80 % dos amadores brasileiros treinam sem coach, o produto
  os exclui". Isso não reflete o modelo de produto: **o Omni Runner é uma
  plataforma voltada para assessorias esportivas** — todo atleta amador
  que usa o produto está vinculado a uma assessoria / coaching_group com
  um coach responsável por prescrever o plano. O cenário "solo runner
  sem coach" não é uma persona suportada e não será suportada.

  O caminho real de prescrição de plano para amador já existe em dois
  módulos desta onda:

  - **L23-06 periodization wizard** (`portal/src/lib/periodization/`) —
    coach escolhe `raceTarget + totalWeeks + athleteLevel` na wizard,
    gera `PeriodizationPlan` base → build → peak → taper, materializa em
    `training_plan_weeks`. Nunca é chamado diretamente pelo atleta.
  - **L23-05 workout template library** — catálogo canônico de workouts
    que o coach usa para preencher o plano semanal após o macro-bloco da
    wizard. Template library também é coach-facing only.
  - **Periodização existente** em
    `supabase/migrations/20260407000000_training_plan_module.sql`
    (~1500 linhas) já modela o fluxo coach → atleta end-to-end.

  Não há gap funcional a fechar. Qualquer futura feature "plano
  auto-gerado" só existiria para **auxiliar coaches** (ex: sugestão de
  primeiro draft que o coach edita), nunca como atalho para contornar a
  assessoria. Se tal feature for eventualmente priorizada, ela vira um
  finding novo com audit_ref diferente.
---
# [L22-03] Plano semanal pessoal ausente para solo runner (scope-mismatch)
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟢 Safe (N/A) · **Onda:** 1 · **Status:** safe
**Camada:** —
**Personas impactadas:** n/a (persona inexistente)

## Achado (original)
— "Se amador não tem coach (não faz parte de assessoria paga), sem plano. Training plan module presume coach-driven."

## Avaliação

A persona "amador sem coach" **não existe** neste produto. O Omni Runner é
uma plataforma de assessorias esportivas — todo amador é membro de uma
`coaching_groups` com coach responsável. A premissa do finding ("80 % dos
amadores BR treinam sem coach, o produto os exclui") é invertida: o
produto **intencionalmente** atende apenas o 20 % que contratou assessoria,
porque o modelo de negócio é B2B2C (assessoria paga → atletas recebem).

## Caminho real

Plano do atleta amador chega via **coach** usando:

1. **L23-06 periodization wizard** — coach monta macro-blocos base/build/peak/taper.
2. **L23-05 workout template library** — coach preenche cada semana com sessions.
3. `training_plan_weeks` + `training_plan_workouts` (schema existente da migration `20260407000000_training_plan_module.sql`) carregam o resultado para o app do atleta.

## Decisão

- Status definido como `safe` — não há bug, é feature por design.
- Nenhum código novo.
- Nenhum teste novo.
- Documentado como referência para futuros auditores não reviver o gap.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.3]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.3).
- `2026-04-21` — Fechado como **scope-mismatch / N/A**. Produto é
  assessoria-centric; persona "solo runner sem coach" não suportada.
  Cross-refs: L23-05 workout template library, L23-06 periodization
  wizard.
