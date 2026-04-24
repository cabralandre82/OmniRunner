---
id: L22-11
audit_ref: "22.11"
lens: 22
title: "Corrida em esteira sem GPS"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["anti-cheat", "gps", "personas", "athlete-amateur"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - b2007d6

owner: mobile+anti-cheat
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`. Modo
  treadmill com toggle no recording, distância pre-set (5/8/
  10/15km), HR via BLE, cadência via accelerometer. Anti-cheat
  L01-43 carve-out: skip GPS-checks, mantém pace/HR/duration
  plausibility. Excluído de leaderboard GPS, incluído em
  volume/streak/badges não-geo. Wave 4 fase H.
---
# [L22-11] Corrida em esteira sem GPS
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
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