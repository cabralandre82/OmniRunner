---
id: L13-03
audit_ref: "13.3"
lens: 13
title: "Middleware executa query DB a cada request autenticado"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "middleware", "performance", "cache"]
files:
  - portal/src/middleware.ts
  - portal/src/lib/route-policy-cache.ts
  - portal/src/lib/route-policy-cache.test.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/route-policy-cache.test.ts
linked_issues: []
linked_prs:
  - "commit:810d4d9"
owner: portal
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido em 2026-04-17 introduzindo um LRU process-local em
  `portal/src/lib/route-policy-cache.ts` para a query de
  `coaching_members`:

    - **TTL: 60 s** — limita a janela de staleness em demoções de
      role; documentada como decisão consciente no header do módulo.
    - **MAX_ENTRIES: 5 000** — cap de memória que protege contra
      blowup quando uma instância vê muitos usuários distintos em
      uma janela quente (cron iterando atletas, etc.).
    - **Negative caching** com sentinel `MEMBERSHIP_NONE` — usuário
      sem membership na query também é cacheado pelo mesmo TTL,
      evitando que um spammer dispare uma round-trip por request
      após perder a conta.
    - **Chave `${userId}:${groupId}`** — cross-tenant poisoning
      impossível por construção; valor armazenado é apenas `role`
      (ou sentinel), zero PII.
    - **API de invalidação** (`invalidateMembership`,
      `invalidateAllForUser`, `clearMembershipCache`) exposta para
      consumidores de mutações (admin add/remove/role-change). Wiring
      nas routes de mutação fica como follow-up de baixo esforço
      (toda escrita em `/api/coaching-members/**` deve chamar
      `invalidateMembership(userId, groupId)`).
    - **TTL hook de teste** (`setMembershipCacheTTLForTests`) permite
      validar expiry sem `vi.useFakeTimers()` global.

  Impacto medido em desenvolvimento: dashboard com 15 RSC + 8 fetch
  passa de 23 round-trips para no máximo 1 por `(user, group)` na
  janela quente.

  Defense-in-depth: middleware também valida o `role` retornado pelo
  DB com `isStaffRole()` (L13-02) antes de gravar no cookie/cache,
  então um valor inesperado nunca permanece no cache.

  Commit `810d4d9`. 13 testes unitários cobrem hit/miss/expiry/
  invalidação/LRU recency.
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