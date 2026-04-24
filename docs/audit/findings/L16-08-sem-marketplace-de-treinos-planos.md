---
id: L16-08
audit_ref: "16.8"
lens: 16
title: "Sem marketplace de treinos/planos"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["migration"]
files:
  - docs/integrations/MARKETPLACE_TRAINING_PLANS.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product+platform
runbook: docs/integrations/MARKETPLACE_TRAINING_PLANS.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Spec ratificado em `docs/integrations/MARKETPLACE_TRAINING_PLANS.md`.
  Decisão: `plan_listings` + `plan_purchases` com checkout via Stripe
  (não OmniCoin em v1). Receita de marketplace flui pela infra
  existente de `platform_revenue` + `custody`. Refund/chargeback
  tratados pelo webhook Stripe já estabilizado (L18-02). Implementação
  Wave 3+.
---
# [L16-08] Sem marketplace de treinos/planos
> **Lente:** 16 — CAO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `training-plan` module existe (1500+ linhas de migration). Mas não há "comprar plano de maratona do Coach X" entre grupos.
## Correção proposta

— `plan_listings` table + checkout com `platform_revenue` recebendo taxa de marketplace.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.8).