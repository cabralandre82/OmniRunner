---
id: L08-12
audit_ref: "8.12"
lens: 8
title: "Mobile: analytics não enviados quando offline"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "ux", "reliability"]
files:
  - docs/runbooks/MOBILE_OFFLINE_ANALYTICS.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs:
  - d3488b4
  - ba3c71e
owner: mobile
runbook: docs/runbooks/MOBILE_OFFLINE_ANALYTICS.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Spec ratified in docs/runbooks/MOBILE_OFFLINE_ANALYTICS.md:
  pending_events Drift table buffers fire-and-forget events
  when device is offline (or inline INSERT raises network
  errors); WorkManager / BGProcessingTask job
  omni-product-events-flush wakes on connectivity_changed +
  every 30 minutes, batches up to 100 oldest, drops dead-letter
  rows after 10 attempts to bound on-device storage. One-shot
  events use the same 23505-swallow path as the online path
  to keep the partial unique index on product_events
  authoritative.
---
# [L08-12] Mobile: analytics não enviados quando offline
> **Lente:** 8 — CDO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `_insert` falha silenciosamente. Eventos de onboarding offline são perdidos.
## Correção proposta

— Queue local em Drift `pending_events`, flush ao conectar.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.12).