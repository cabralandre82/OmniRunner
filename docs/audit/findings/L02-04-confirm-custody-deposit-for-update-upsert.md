---
id: L02-04
audit_ref: "2.4"
lens: 2
title: "confirm_custody_deposit — FOR UPDATE + UPSERT"
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
# [L02-04] confirm_custody_deposit — FOR UPDATE + UPSERT
> **Lente:** 2 — CTO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`20260228170000:325-352` faz `SELECT … FOR UPDATE` na linha do depósito (linha 336), depois UPSERT em `custody_accounts` com `ON CONFLICT DO UPDATE`. Seguro contra double-confirmation.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.4).