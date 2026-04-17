---
id: L23-07
audit_ref: "23.7"
lens: 23
title: "Análise coletiva (grupo) limitada"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["personas", "coach"]
files: []
correction_type: code
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L23-07] Análise coletiva (grupo) limitada
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `coaching_kpis_daily` tem total. Coach quer:

- Distribuição de volume semanal (gráfico de cauda)
- Atletas correndo mais do que recomendado
- Atletas não correndo (attrition risk)
- Progresso coletivo vs mês anterior
## Correção proposta

— Views materializadas + `/platform/analytics/group-overview`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.7).