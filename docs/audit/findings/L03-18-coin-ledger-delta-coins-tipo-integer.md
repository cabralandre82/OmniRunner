---
id: L03-18
audit_ref: "3.18"
lens: 3
title: "coin_ledger.delta_coins — Tipo integer"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["finance", "migration"]
files: []
correction_type: code
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
# [L03-18] coin_ledger.delta_coins — Tipo integer
> **Lente:** 3 — CFO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`coin_ledger.delta_coins integer` (migration base 20260221000022). Integer evita IEEE 754 e arredondamento. Bom design. Peg 1 coin = $1 USD → coin count = USD integer.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.18]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.18).