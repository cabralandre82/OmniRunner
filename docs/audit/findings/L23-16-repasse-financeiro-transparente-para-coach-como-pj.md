---
id: L23-16
audit_ref: "23.16"
lens: 23
title: "Repasse financeiro transparente para coach como PJ"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["finance", "personas", "coach", "portal"]
files:
  - docs/product/COACH_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - "k12-pending"

owner: product+backend+portal
runbook: docs/product/COACH_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/COACH_BASELINE.md` § 2
  (Coach PJ earnings dashboard). ZERO novas colunas —
  view `coach_earnings_monthly` agrega
  `billing_purchases` já com todos os cents breakdown
  (amount, platform_fee, provider_fee, fx_spread,
  net_to_seller, refunded). RLS via
  `security_invoker=true`. Portal page com month picker
  + KPI strip + tabela expandível + extrato mensal PDF
  on-demand (reutiliza infra `@react-pdf` de L22-15 W5-B).
  Fee explainer transparente. Ship Wave 4 fase W4-Q
  (depois do PDF infra, herda a renderização).
---
# [L23-16] Repasse financeiro transparente para coach como PJ
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach quer ver: "no mês recebi R$ X bruto; descontadas taxas (Y%), líquido R$ Z; posso sacar quando?". Dashboard financeiro simples.
## Correção proposta

— `/platform/billing/earnings` com breakdown mensal + previsão de saque.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.16).
- `2026-04-24` — Consolidado em `docs/product/COACH_BASELINE.md` § 2 (batch K12); implementação Wave 4 fase W4-Q.
