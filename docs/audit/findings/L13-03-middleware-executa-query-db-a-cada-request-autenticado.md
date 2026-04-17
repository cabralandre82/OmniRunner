---
id: L13-03
audit_ref: "13.3"
lens: 13
title: "Middleware executa query DB a cada request autenticado"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "testing"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L13-03] Middleware executa query DB a cada request autenticado
> **Lente:** 13 — Middleware · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linhas 81-88: `SELECT role FROM coaching_members WHERE user_id=X AND group_id=Y` a **cada request**. Linhas 49-53: `SELECT platform_role FROM profiles WHERE id=X` a cada request em `/platform/**`.

Para uma navegação normal em `/platform/dashboard` que traz 15 RSCs + 8 chamadas `/api/*`, são **23 queries a `profiles`** — cada uma com round-trip Supabase ~50 ms.
## Risco / Impacto

— Latência percebida em dashboard administrativo pior que produto. Em pico, esgota pool de conexões Supabase (default 15 conexões por instância).

## Correção proposta

—

1. **Edge cache em cookie assinado** (JWT-claim-lite):

```typescript
// Include platform_role and membership inside the supabase JWT as custom claims
// via a DB function + auth.jwt() hook (Supabase "Add custom claims" feature).
// Then read from JWT on every request with zero DB hit.
```

2. **Se manter query**, cachear em Redis por 60 s:

```typescript
const cacheKey = `auth:${user.id}:${groupId}`;
const cached = await getRedis().get(cacheKey);
if (cached) { role = cached; } else {
  // ... query ...
  await getRedis().setex(cacheKey, 60, membership.role);
}
```

3. **Invalidation**: ao mudar `platform_role` ou `coaching_members.role`, invalidar via trigger SQL + `PERFORM pg_notify('cache_invalidate', …)`.

## Teste de regressão

— `middleware.perf.test.ts`: navegar 5 páginas → total de DB queries cachadas via spy deve ser ≤ 1 (depois cache hit) em request 2+.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.3).