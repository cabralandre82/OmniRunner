---
id: L21-14
audit_ref: "21.14"
lens: 21
title: "Sem race predictor (VDOT/Riegel)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "edge-function", "personas", "athlete-pro"]
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
# [L21-14] Sem race predictor (VDOT/Riegel)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— "Se você correu 10 km em 40 min, sua maratona é ~3:05:xx". Calculador VDOT Jack Daniels é essencial para planejamento.
## Correção proposta

— Edge Function `predict-race` + UI em `athlete_evolution_screen.dart`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.14).