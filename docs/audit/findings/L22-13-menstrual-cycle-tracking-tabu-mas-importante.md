---
id: L22-13
audit_ref: "22.13"
lens: 22
title: "Menstrual cycle tracking — tabu mas importante"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["personas", "athlete-amateur"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L22-13] Menstrual cycle tracking — tabu mas importante
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
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