---
id: L21-14
audit_ref: "21.14"
lens: 21
title: "Sem race predictor (VDOT/Riegel)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "edge-function", "personas", "athlete-pro"]
files:
  - docs/product/RACE_PREDICTOR.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 32ef899

owner: product
runbook: docs/product/RACE_PREDICTOR.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Spec ratificado em `docs/product/RACE_PREDICTOR.md`. Decisão:
  estimador 100% client-side, blend Riegel + VDOT + McMillan-aprox
  com ajuste de fitness (CTL) clamped em ±5%. Detecção automática
  de seed-race com 4 critérios (race tag, distância padrão, std-dev
  de pace, sem auto-pause). Sem trail/ultra > 100km e sem 'first-
  ever distance' (sugere time-trial). Implementação Wave 4.
---
# [L21-14] Sem race predictor (VDOT/Riegel)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
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