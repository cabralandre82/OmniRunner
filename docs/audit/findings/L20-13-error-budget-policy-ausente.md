---
id: L20-13
audit_ref: "20.13"
lens: 20
title: "Error budget policy ausente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["rls", "migration"]
files:
  - docs/ERROR_BUDGET_POLICY.md
correction_type: docs
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
# [L20-13] Error budget policy ausente
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Sem policy "se consumiu 80% error budget, pausa deploys de features até restaurar".
## Correção proposta

— `docs/ERROR_BUDGET_POLICY.md`. Automation: GitHub check bloqueia merge para main se error budget consumed > 80%.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.13).