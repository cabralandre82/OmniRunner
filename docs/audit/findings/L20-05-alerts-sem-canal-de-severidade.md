---
id: L20-05
audit_ref: "20.5"
lens: 20
title: "Alerts sem canal de severidade"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["webhook", "observability"]
files: []
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
# [L20-05] Alerts sem canal de severidade
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Sentry envia email para catch-all. Incidents P1 (financial) chegam com mesmo weight que P4 (console.warn).
## Correção proposta

— Roteamento:

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.5).