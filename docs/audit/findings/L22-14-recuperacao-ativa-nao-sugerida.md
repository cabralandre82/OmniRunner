---
id: L22-14
audit_ref: "22.14"
lens: 22
title: "Recuperação ativa não sugerida"
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
linked_prs: []
owner: product+coaching
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`. ACWR
  (Gabbett 2016) com thresholds 1.3 (soft suggestion) e 1.5
  (mandatory recovery, override possível mas audit-logged).
  Trigger adicional `back_to_back` quando últimos 2 dias
  tiveram intensity≥tempo. `daily_recommendations.reason` enum
  novo. Coach pode desligar nudges em `athlete_settings`. Wave
  4 fase I.
---
# [L22-14] Recuperação ativa não sugerida
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Amador faz 3 corridas seguidas pesadas → lesão. Sem sistema que sugira "descansar" ou "caminhada".
## Correção proposta

— Regra heurística em `generate-fit-workout`: se últimos 3 dias tiveram TSS alto → próximo treino é "descanso ativo/caminhada 20 min".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.14).