---
id: L23-06
audit_ref: "23.6"
lens: 23
title: "Plano mensal/trimestral não periodizado"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["personas", "coach"]
files:
  - portal/src/lib/periodization/types.ts
  - portal/src/lib/periodization/generate-periodization.ts
  - portal/src/app/api/training-plan/wizard/route.ts
  - tools/audit/check-periodization-template.ts
  - docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - portal/src/lib/periodization/__tests__/generate-periodization.test.ts
linked_issues: []
linked_prs:
  - local:b4f36a9
owner: unassigned
runbook: docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L23-06] Plano mensal/trimestral não periodizado
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Módulo `training-plan` (1500 linhas) presumivelmente lida com plans. Auditoria rápida não confirma **periodização** (base → build → peak → taper).
## Correção proposta

— Template wizard: "Meia-maratona em 12 semanas" gera periodização automática ajustada ao atleta. Coach edita blocks (não workouts individuais) — escala.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.6).
- `2026-04-21` — Fixed via commit `b4f36a9`. Pure periodization generator
  ships for 4 race targets × 3 athlete levels with base → build → peak →
  taper blocks; auth-gated POST wizard route + 21-case vitest suite +
  38-check CI guard (`audit:periodization-template`) + runbook
  `docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md`.