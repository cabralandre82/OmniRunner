---
id: L15-06
audit_ref: "15.6"
lens: 15
title: "Sem A/B testing framework"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["ux"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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