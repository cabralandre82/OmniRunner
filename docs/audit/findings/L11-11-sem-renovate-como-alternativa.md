---
id: L11-11
audit_ref: "11.11"
lens: 11
title: "Sem Renovate como alternativa"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: []
files:
  - docs/runbooks/RENOVATE_VS_DEPENDABOT.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - d3488b4
  - 41699e9
owner: platform
runbook: docs/runbooks/RENOVATE_VS_DEPENDABOT.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Decision ratified in docs/runbooks/RENOVATE_VS_DEPENDABOT.md:
  stay on Dependabot (mono-repo + the existing 22 groups in
  .github/dependabot.yml deliver the same per-ecosystem PR
  shape Renovate would). Re-evaluation triggers: repo count > 1,
  >2 h/week patch shepherding for 2 months, > 5 lockfile drifts/qtr,
  or Dependabot groups: semantics regression. Otherwise re-ratify
  in 2026 Q4.
---
# [L11-11] Sem Renovate como alternativa
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Apenas Dependabot. Renovate tem melhor agrupamento, lockfile maintenance, merge automático de patches seguros.
## Correção proposta

— Adicionar `renovate.json` ou migrar de Dependabot.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.11).