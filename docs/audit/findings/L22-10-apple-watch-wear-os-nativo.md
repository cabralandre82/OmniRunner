---
id: L22-10
audit_ref: "22.10"
lens: 22
title: "Apple Watch / Wear OS nativo"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "personas", "athlete-amateur"]
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
# [L22-10] Apple Watch / Wear OS nativo
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `watch_bridge/` existe com `watch_session_payload.dart`. Auditoria superficial: provavelmente não tem WatchOS complication nem GarminIQ data field.
## Correção proposta

— Roadmap: app companion para WatchOS + Wear OS com start/stop/pause nativo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.10).