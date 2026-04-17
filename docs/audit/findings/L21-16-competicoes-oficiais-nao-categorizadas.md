---
id: L21-16
audit_ref: "21.16"
lens: 21
title: "Competições oficiais não categorizadas"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["migration", "personas", "athlete-pro"]
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
# [L21-16] Competições oficiais não categorizadas
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
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