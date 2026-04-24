---
id: L21-16
audit_ref: "21.16"
lens: 21
title: "Competições oficiais não categorizadas"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["migration", "personas", "athlete-pro"]
files:
  - docs/product/ATHLETE_PRO_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product+platform
runbook: docs/product/ATHLETE_PRO_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_PRO_BASELINE.md`. Tabela
  `race_results` separada de `sessions` com bib/chip/category/
  place. Verificação Wave 5 via event-partner CSV import. Race
  predictor (L21-14) usa `chip_time_s` quando disponível. Wave
  4 fase B.
---
# [L21-16] Competições oficiais não categorizadas
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Atleta marca uma corrida como "competição" via UI ad-hoc. Sem tabela `race_results` com oficial/chip/bib/categoria.
## Correção proposta

— `CREATE TABLE race_results (user_id, event_name, date, distance_m, chip_time_s, bib, category, place_overall, place_category);`

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.16).