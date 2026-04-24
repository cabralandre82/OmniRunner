---
id: L18-09
audit_ref: "18.9"
lens: 18
title: "Sem domain events em audit_log"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "audit", "schema-evolution", "fixed"]
files:
  - supabase/migrations/20260421830000_l18_09_audit_event_schema_version.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - "supabase/migrations/20260421830000_l18_09_audit_event_schema_version.sql (in-migration self-test)"
  - "npm run audit:k2-sql-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — adds event_schema_version int and event_domain text columns
  to public.audit_logs and public.portal_audit_log. event_domain is
  backfilled from split_part(action, '.', 1). NOT VALID CHECK
  asserts dotted-notation action shape (domain.resource.verb…) for
  new rows, leaving legacy rows undisturbed (operator validates after
  cleanup). New index (event_domain, created_at DESC) speeds per-domain
  queries. CI guard verifies presence of all three primitives.
---
# [L18-09] Sem domain events em audit_log
> **Lente:** 18 — Principal Eng · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `audit_logs` registra action string + metadata. Sem tipagem — `"custody.deposit.confirmed"` ao lado de `"user.login"` sem distinguir escopos.
## Correção proposta

— Schema versionado em `audit_logs.event_schema_version`; eventos tipados com Zod:

```typescript
const CustodyDepositConfirmedEvent = z.object({
  event: z.literal("custody.deposit.confirmed"),
  v: z.literal(1),
  deposit_id: z.string().uuid(),
  amount_usd: z.number(),
  actor_id: z.string().uuid(),
});
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.9).