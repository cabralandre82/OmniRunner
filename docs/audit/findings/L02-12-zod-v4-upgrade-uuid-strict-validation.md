---
id: L02-12
audit_ref: "2.12"
lens: 2
title: "Zod v4 upgrade — UUID strict validation"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["integration", "mobile", "portal", "schemas", "fixed"]
files:
  - portal/src/lib/schemas/uuid-policy.ts
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: true
tests:
  - "npm run audit:k3-domain-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — codified the UUID-validation policy as three Zod helpers:
    omniUuid()                       → strict z.string().uuid() (internal IDs)
    externalIntegrationId(label)     → opaque string with min/max bounds
    correlationToken(label, opts)    → free-form correlation token
  The split prevents 'z.string().uuid()' creep onto external IDs (Strava
  athlete numbers, Stripe payment IDs) that do NOT have UUID shape.
  New schemas should import from portal/src/lib/schemas/uuid-policy.ts;
  bare z.string().uuid() is now reserved for OmniRunner-issued UUIDs.
---
# [L02-12] Zod v4 upgrade — UUID strict validation
> **Lente:** 2 — CTO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Todos (formulários)
## Achado
`portal/src/lib/schemas.ts:4,24,76,92,98,108,115` usam `z.string().uuid(...)`. Zod v4 mudou `uuid()` para validar strict RFC 4122 (exige versão 1-5 em posição específica). UUIDs gerados por `gen_random_uuid()` (Postgres) são v4 — ok. Mas UUIDs de integrações externas (Strava `activity_id` legado) **não são UUIDs**, são inteiros. Se algum schema aceita IDs externos como `z.string().uuid()`, vai quebrar.
## Risco / Impacto

Forms/endpoints quebrarem silenciosamente após upgrade de Zod.

## Correção proposta

Auditar todos `z.string().uuid()` contra o schema do banco. Para IDs de integrações externas não-UUID, usar `z.string().min(1).max(100)` ou regex específico.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.12).