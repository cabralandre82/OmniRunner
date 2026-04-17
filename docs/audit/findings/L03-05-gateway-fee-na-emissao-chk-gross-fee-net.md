---
id: L03-05
audit_ref: "3.5"
lens: 3
title: "Gateway fee na emissão — chk_gross_fee_net"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: []
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
# [L03-05] Gateway fee na emissão — chk_gross_fee_net
> **Lente:** 3 — CFO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`20260303100000:30-34` garante `gross = net + fee`. Coerente com o modelo Option B (assessoria paga bruto, platform recebe net após Stripe/MP).
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.5).