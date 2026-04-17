---
id: L06-10
audit_ref: "6.10"
lens: 6
title: "Não há SLO documentado"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "reliability"]
files:
  - docs/SLO.md
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
# [L06-10] Não há SLO documentado
> **Lente:** 6 — COO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `docs/` não define SLO por endpoint/módulo. Ex.: "/api/custody/withdraw: P99 < 500 ms, error rate < 0.1%". Sem SLO, time priori­za incorretamente.
## Correção proposta

— `docs/SLO.md` listando os 15 endpoints críticos + thresholds de erro + SLA de incidentes.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.10).