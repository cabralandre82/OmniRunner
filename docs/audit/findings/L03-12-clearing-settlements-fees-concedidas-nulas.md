---
id: L03-12
audit_ref: "3.12"
lens: 3
title: "clearing_settlements — Fees concedidas nulas"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["finance"]
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
# [L03-12] clearing_settlements — Fees concedidas nulas
> **Lente:** 3 — CFO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`settle_clearing` (`20260228170000:186-190`) só insere em `platform_revenue` se `v_fee > 0`. Para fee_rate=0 (custom), nenhum insert. OK.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.12).