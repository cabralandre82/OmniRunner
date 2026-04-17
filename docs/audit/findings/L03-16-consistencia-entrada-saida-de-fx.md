---
id: L03-16
audit_ref: "3.16"
lens: 3
title: "Consistência entrada–saída de FX"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal"]
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
# [L03-16] Consistência entrada–saída de FX
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
_(sem descrição detalhada — ver relatório original em `docs/audit/parts/`)_
## Correção proposta

Remover `fx_rate` do client-side; buscar rate server-side.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.16).