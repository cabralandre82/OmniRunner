---
id: L19-08
audit_ref: "19.8"
lens: 19
title: "Constraints CHECK sem name padronizado"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration"]
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
# [L19-08] Constraints CHECK sem name padronizado
> **Lente:** 19 — DBA · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Algumas tabelas têm `chk_peg_1_to_1`, outras usam nome auto-gerado `custody_accounts_total_deposited_usd_check`. Em erros, frontend mostra nome feio.
## Correção proposta

— Convenção: `chk_<table>_<regra>`. Alterar constraints não-nomeadas com `ALTER TABLE … RENAME CONSTRAINT`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.8).