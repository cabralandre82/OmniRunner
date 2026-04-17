---
id: L22-11
audit_ref: "22.11"
lens: 22
title: "Corrida em esteira sem GPS"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["anti-cheat", "gps", "personas", "athlete-amateur"]
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
# [L22-11] Corrida em esteira sem GPS
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Anti-cheat exige GPS points `>= MIN_POINTS = 5`. Treino em esteira (não há GPS) é reprovado.
## Correção proposta

— Modo "treadmill": aceita distância declarada manualmente, FC via BLE, cadence via phone accelerometer. Flag distinto em `sessions.recording_type = 'treadmill'`; não conta para rankings GPS mas conta para volume/frequência.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.11).