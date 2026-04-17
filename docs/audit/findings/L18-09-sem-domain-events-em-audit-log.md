---
id: L18-09
audit_ref: "18.9"
lens: 18
title: "Sem domain events em audit_log"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance"]
files: []
correction_type: code
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