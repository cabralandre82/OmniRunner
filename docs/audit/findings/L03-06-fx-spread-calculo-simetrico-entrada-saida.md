---
id: L03-06
audit_ref: "3.6"
lens: 3
title: "FX spread — Cálculo simétrico entrada/saída"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "portal", "reliability", "disclosure", "fixed"]
files:
  - docs/legal/FX_SPREAD_DISCLOSURE.md
  - tools/audit/check-k3-domain-fixes.ts
correction_type: docs
test_required: true
tests:
  - "npm run audit:k3-domain-fixes"
linked_issues: []
linked_prs: []
owner: finance
runbook: docs/legal/FX_SPREAD_DISCLOSURE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — disclosure doc formalising:
    • spread default 0.75% applied PER LEG (entrada/saída)
    • round-trip cost ≈ 1.5% (1 - (1-0.0075)^2 = 0.014944)
    • concrete worked example in BRL/USD
    • UI surfaces requiring disclosure (deposit confirm, withdrawal
      confirm, settlement preview)
    • implementation references (custody.ts, fx_rates table, IOF
      cumulation note for Decreto 6.306/2007 art. 15-B)
  Document keys off check-k3-domain-fixes guard so future drift in
  spread defaults can't ship without updating this disclosure.
---
# [L03-06] FX spread — Cálculo simétrico entrada/saída
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
`portal/src/lib/custody.ts:214-243`:
## Risco / Impacto

Baixo-médio — usuários podem achar que perda é 0.75% (single leg) e se surpreender com 1.5% round-trip.

## Correção proposta

Documentar em ajuda/FAQ. Opcional: cobrar spread só no on-ramp (entrada), mantendo saída a FX mid-market.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.6).