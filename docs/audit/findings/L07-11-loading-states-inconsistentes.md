---
id: L07-11
audit_ref: "7.11"
lens: 7
title: "Loading states inconsistentes"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile"]
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
# [L07-11] Loading states inconsistentes
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Algumas listas mostram skeleton, outras spinner, outras branco. Mesma tela entre mobile/web. Coerência.
## Correção proposta

— Design system: todas as listas usam `<SkeletonCard rows={5} />`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.11).