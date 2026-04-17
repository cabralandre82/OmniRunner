---
id: L01-45
audit_ref: "1.45"
lens: 1
title: "fee_type — 'fx_spread' ausente do endpoint admin"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal"]
files:
  - portal/src/app/api/platform/fees/route.ts
correction_type: process
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
# [L01-45] fee_type — 'fx_spread' ausente do endpoint admin
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** platform_admin
## Achado
`portal/src/app/api/platform/fees/route.ts:10` aceita `z.enum(["clearing","swap","maintenance","billing_split"])` — sem `'fx_spread'`. UI platform não consegue ajustar FX spread via endpoint. Admin precisa rodar SQL manual.
## Correção proposta

Ver 1.13. Adicionar `"fx_spread"`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.45]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.45).