---
id: L19-04
audit_ref: "19.4"
lens: 19
title: "idx_ledger_user vs idx_coin_ledger_user_created — evoluções sem limpeza"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "performance", "reliability"]
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
# [L19-04] idx_ledger_user vs idx_coin_ledger_user_created — evoluções sem limpeza
> **Lente:** 19 — DBA · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Migration 2026-02-18 cria `idx_ledger_user`; migration 2026-03-08 cria `idx_coin_ledger_user_created`. Nomenclatura inconsistente; provavelmente ambos persistem.
## Correção proposta

— Migration `CREATE INDEX CONCURRENTLY idx_X; DROP INDEX CONCURRENTLY idx_Y;` para trocar sem lock.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.4).