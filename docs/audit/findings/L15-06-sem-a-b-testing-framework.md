---
id: L15-06
audit_ref: "15.6"
lens: 15
title: "Sem A/B testing framework"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["ux", "platform", "experimentation"]
files:
  - docs/runbooks/AB_TESTING_FRAMEWORK.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product+platform
runbook: docs/runbooks/AB_TESTING_FRAMEWORK.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Decisão ratificada em
  `docs/runbooks/AB_TESTING_FRAMEWORK.md`. **GrowthBook
  self-hosted no Render + PostHog backend**. Variant
  assignment via stable hash de `user_id`/`device_id`,
  mutually-exclusive namespaces para experimentos
  relacionados, holdout 5%. Eventos `experiment.assigned` em
  `product_events` (L08-09 catalog) → SQL joins sem nova
  pipeline. Guardrails: SRM check diário, auto-stop em
  regressão de signup_rate/error_rate/withdraw_completion,
  mobile rollout 24h após portal, registry obrigatório em
  `EXPERIMENT_REGISTRY.md`. CI guard
  `audit:no-experiments-on-finance` bloqueia
  `getFeatureValue` em `app/api/{custody,swap,coins,
  distribute-coins,checkout}`. Implementação Wave 3.
---
# [L15-06] Sem A/B testing framework
> **Lente:** 15 — CMO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Grep `flag|experiment|split|statsig|amplitude|growthbook` → zero. Pricing, onboarding, CTA textos — todos decididos por gut feeling.
## Correção proposta

— GrowthBook (self-hosted) ou Flagsmith; experimentos logam variante em `product_events`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.6).