---
id: L14-04
audit_ref: "14.4"
lens: 14
title: "Rate-limit por IP em swap/custody vs por user/group"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["rate-limit", "mobile", "portal"]
files:
  - portal/src/lib/api/rate-limit-key.ts
  - portal/src/lib/api/rate-limit-key.test.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/app/api/custody/route.ts
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/clearing/route.ts
  - portal/src/app/api/distribute-coins/route.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/api/rate-limit-key.test.ts
linked_issues: []
linked_prs:
  - 3ac1496
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in commit `3ac1496`. New `lib/api/rate-limit-key.ts` derives
  identity in the order `group_id → user_id → SHA1-hashed IP →
  anon`. Namespaces (`:g:` / `:u:` / `:ip:` / `:anon:`) prevent
  collision between identity kinds. Raw IPs are never written to
  keys (PII hygiene). Applied to swap, custody, custody/withdraw,
  clearing and distribute-coins; in each route the cookie
  `portal_group_id` is read pre-auth so even GET-with-rate-limit
  buckets per-tenant when the user has a session.
---
# [L14-04] Rate-limit por IP em swap/custody vs por user/group
> **Lente:** 14 — Contracts · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/swap/route.ts:60,76` faz `rateLimit("swap:" + ip, …)`. IP atrás de CGN/NAT móvel é compartilhado entre milhares.
## Risco / Impacto

— Vários grupos compartilham mesmo IP → um grupo ativo bloqueia outros.

## Correção proposta

—

```typescript
const key = `swap:${auth.groupId ?? ip}`;
const rl = await rateLimit(key, { maxRequests: 30, windowMs: 60_000 });
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.4).