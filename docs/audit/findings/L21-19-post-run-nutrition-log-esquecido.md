---
id: L21-19
audit_ref: "21.19"
lens: 21
title: "Post-run nutrition log esquecido"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["personas", "athlete-pro"]
files:
  - docs/product/ATHLETE_PRO_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product+mobile
runbook: docs/product/ATHLETE_PRO_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_PRO_BASELINE.md`. Push
  20min após long-run (≥12km, ≥1h, workout_type long_run/race
  ou volume > 1.3× 7d-avg). UI: 5 chips de categoria, sem
  macros (friction kills). Suprime push se Apple Health/HC já
  logou refeição. Wave 4 fase E.
---
# [L21-19] Post-run nutrition log esquecido
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Corrida-longa exige refeição pós; não há lembrete/log de carb window.
## Correção proposta

— Notification push 20 min pós-sessão longa: "Recovery window — logue sua refeição". Para elite opcional, para amador educacional.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.19).