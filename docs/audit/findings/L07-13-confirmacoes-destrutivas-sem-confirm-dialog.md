---
id: L07-13
audit_ref: "7.13"
lens: 7
title: "Confirmações destrutivas sem confirm dialog"
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
# [L07-13] Confirmações destrutivas sem confirm dialog
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— "Excluir conta", "Cancelar championship", "Cancelar swap" — auditoria mobile sugere que alguns botões disparam ação direto após tap.
## Correção proposta

— Modal obrigatório com "Digite CONFIRMAR" ou double-tap, com texto explicando consequência ("Esta ação é irreversível").

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.13).