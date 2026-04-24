---
id: L22-13
audit_ref: "22.13"
lens: 22
title: "Menstrual cycle tracking — tabu mas importante"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["personas", "athlete-amateur"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - b2007d6

owner: product+legal+platform
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`. Opt-in
  dedicado (LGPD Art. 11), tabela `athlete_cycle_data` com
  pgsodium em colunas sensíveis. Coach NUNCA vê salvo per-row
  `shared_with_coach=true` (bar mais alta que recovery data).
  Sem forecasting (escopo medical-device). Hard-delete em
  opt-out + `consent_registry` event. Wave 4 fase K (último
  por exigir mais review legal).
---
# [L22-13] Menstrual cycle tracking — tabu mas importante
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Treino feminino é afetado por ciclo. Sem integração com cycle tracker.
## Correção proposta

— Opt-in em `athlete_health_data.cycle_phase`; ajusta sugestões de intensidade (luteal vs folicular). Grande diferencial para público feminino (50% do mercado de running BR e crescendo).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.13).