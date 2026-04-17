---
id: L01-08
audit_ref: "1.8"
lens: 1
title: "GET /api/liveness — OK"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/app/api/liveness/route.ts
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
# [L01-08] GET /api/liveness — OK
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
`portal/src/app/api/liveness/route.ts:6-22` só retorna `{status, ts, latencyMs}`. Nenhum leak.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.8).