---
id: L01-47
audit_ref: "1.47"
lens: 1
title: "executeWithdrawal — execute_withdrawal RPC sem código mostrado"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["finance", "portal", "migration", "reliability"]
files:
  - portal/src/lib/custody.ts
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
# [L01-47] executeWithdrawal — execute_withdrawal RPC sem código mostrado
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
Chamada em `portal/src/lib/custody.ts:372-376`, mas a implementação SQL não foi lida nesta parte. Precisa verificar: FOR UPDATE em `custody_accounts`, verificação de `status='pending'`, idempotência por withdrawalId.
## Correção proposta

Re-auditar migration que cria `execute_withdrawal`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.47]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.47).