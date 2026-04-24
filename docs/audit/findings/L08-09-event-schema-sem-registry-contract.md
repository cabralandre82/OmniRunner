---
id: L08-09
audit_ref: "8.9"
lens: 8
title: "Event schema sem registry / contract"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - docs/analytics/EVENT_CATALOG.md
  - portal/src/lib/product-event-schema.ts
  - omni_runner/lib/core/analytics/product_event_tracker.dart
  - tools/audit/check-event-catalog.ts
  - package.json
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 3af9c9b
  - 15a8b4b
owner: data+product
runbook: docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Canonical event registry is now docs/analytics/EVENT_CATALOG.md
  with the existing TS schema (portal/src/lib/product-event-schema.ts)
  + Dart tracker (ProductEvents.allowedNames/allowedPropertyKeys) +
  Postgres trigger fn_validate_product_event() as the three runtime
  enforcement points. CI guard tools/audit/check-event-catalog.ts
  asserts the catalog stays in sync with the TS constants
  (8 events + 18 property keys); the existing integration test
  tools/test_l08_01_02_product_events_hardening.ts covers TS↔SQL↔Dart
  drift at runtime.
---
# [L08-09] Event schema sem registry / contract
> **Lente:** 8 — CDO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `ProductEvents` é uma classe com constantes. Novos events são criados ad-hoc; sem canonical list nem doc do payload esperado.
## Correção proposta

— `docs/analytics/EVENT_CATALOG.md` + Zod schemas em `portal/src/lib/analytics/events.ts` com tipagem compartilhada entre Flutter (code-gen) e portal.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.9).