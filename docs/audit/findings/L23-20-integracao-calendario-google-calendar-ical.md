---
id: L23-20
audit_ref: "23.20"
lens: 23
title: "Integração calendário (Google Calendar / iCal)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["personas", "coach"]
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
# [L23-20] Integração calendário (Google Calendar / iCal)
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Treino agendado não aparece no Google Calendar do atleta/coach.
## Correção proposta

— `GET /api/athletes/:id/calendar.ics` — feed iCal subscribable. Atleta adiciona URL no Google Cal → treinos aparecem automaticamente.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.20).