---
id: L03-06
audit_ref: "3.6"
lens: 3
title: "FX spread — Cálculo simétrico entrada/saída"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "reliability"]
files:
  - portal/src/lib/custody.ts
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
# [L03-06] FX spread — Cálculo simétrico entrada/saída
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
`portal/src/lib/custody.ts:214-243`:
## Risco / Impacto

Baixo-médio — usuários podem achar que perda é 0.75% (single leg) e se surpreender com 1.5% round-trip.

## Correção proposta

Documentar em ajuda/FAQ. Opcional: cobrar spread só no on-ramp (entrada), mantendo saída a FX mid-market.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.6).