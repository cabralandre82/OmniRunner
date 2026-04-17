---
id: L08-12
audit_ref: "8.12"
lens: 8
title: "Mobile: analytics não enviados quando offline"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "ux", "reliability"]
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
# [L08-12] Mobile: analytics não enviados quando offline
> **Lente:** 8 — CDO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `_insert` falha silenciosamente. Eventos de onboarding offline são perdidos.
## Correção proposta

— Queue local em Drift `pending_events`, flush ao conectar.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.12).