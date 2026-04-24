---
id: L22-10
audit_ref: "22.10"
lens: 22
title: "Apple Watch / Wear OS nativo"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "personas", "athlete-amateur"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - b2007d6

owner: mobile+platform
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`. App
  thin Swift+WatchKit + Kotlin+Wear que espelha start/stop/lap
  do session via `watch_bridge` existente. Standalone (sem
  phone) suporta GPS+HR locais com flush em chunks de 256.
  Anti-cheat existente valida na sync. WatchOS complications/
  GarminIQ ficam fora de v1. Coluna `sessions.recorded_via`.
  Wave 4 fase J.
---
# [L22-10] Apple Watch / Wear OS nativo
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
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