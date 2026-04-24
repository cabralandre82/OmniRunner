---
id: L22-18
audit_ref: "22.18"
lens: 22
title: "Onboarding não pergunta objetivo"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["ux", "personas", "athlete-amateur", "mobile"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "k12-pending"

owner: product+mobile+backend
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`
  § 9 (Onboarding goal step). 5 objetivos canônicos
  (general_health, run_5k, run_10k, run_half_marathon,
  run_marathon) — cobertura >90% do amador;
  "sub-20 5k"/"Boston" ficam em ATHLETE_PRO_BASELINE.
  Target date opcional com bounds de razoabilidade
  (4/8/16/20 semanas mínimas por distância). Colunas
  `profiles.athlete_goal` + `athlete_goal_target_date`
  nullable (backfill via prompt de "complete seu perfil").
  `generate-fit-workout` consome goal quando plano não-
  prescrito. First to ship da Wave 4 K12 (fase W4-L);
  cheapest, highest-leverage.
---
# [L22-18] Onboarding não pergunta objetivo
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Produto trata todos como iguais. "Saúde geral" vs "5K" vs "meia-maratona" exigem periodizações MUITO diferentes.
## Correção proposta

— Step de onboarding "Qual seu objetivo?" com 5 opções + prazo. Plano auto-gerado já respeita.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.18]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.18).
- `2026-04-24` — Consolidado em `docs/product/ATHLETE_AMATEUR_BASELINE.md` § 9 (batch K12); implementação Wave 4 fase W4-L (first-to-ship da Wave 4 K12).
