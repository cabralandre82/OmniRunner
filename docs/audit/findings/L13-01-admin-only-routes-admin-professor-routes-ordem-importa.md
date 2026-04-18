---
id: L13-01
audit_ref: "13.1"
lens: 13
title: "ADMIN_ONLY_ROUTES + ADMIN_PROFESSOR_ROUTES — ordem importa, e está errada"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "middleware", "rbac", "testing"]
files:
  - portal/src/middleware.ts
  - portal/src/lib/route-policy.ts
  - portal/src/lib/route-policy.test.ts
  - portal/src/lib/middleware-routes.test.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/route-policy.test.ts
  - portal/src/lib/middleware-routes.test.ts
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
  Resolvido em 2026-04-17 extraindo a política de rotas para
  `portal/src/lib/route-policy.ts` e expondo um único resolver
  `resolveRouteAccess(pathname, role)` com algoritmo determinístico:

    1. Match em `ADMIN_COACH_ROUTES` (mais específico) → allow se
       role ∈ {admin_master, coach}, senão forbidden.
    2. Match em `ADMIN_ONLY_ROUTES` → allow se role = admin_master.
    3. Caso contrário, `unprotected` (middleware libera após sessão).

  A precedência "match-most-specific-first" é estruturalmente forçada
  pela ordem dos blocos no resolver e coberta por um teste de
  regressão (`coach can access /settings/invite — the core L13-01
  bug`) que falha se as listas forem reordenadas. Defensivamente,
  papéis legados (`professor`) não são silenciosamente promovidos a
  `coach` — devem retornar a 403 para forçar correção na origem.

  Commit `810d4d9` cobre L13-01, L13-02 e L13-03 conjuntamente.
  47 testes vitest novos, suite portal 864 → 893.
---
# [L13-01] ADMIN_ONLY_ROUTES + ADMIN_PROFESSOR_ROUTES — ordem importa, e está errada
> **Lente:** 13 — Middleware · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/middleware.ts:16-23` define:

```16:23:portal/src/middleware.ts
const ADMIN_ONLY_ROUTES = [
  "/credits/history",
  "/credits/request",
  "/billing",
  "/settings",
];

const ADMIN_PROFESSOR_ROUTES = ["/engagement/export", "/settings/invite"];
```

Como linhas 149 e 155 usam `pathname.startsWith(r)` **em sequência**, o `/settings` (ADMIN_ONLY_ROUTES) captura **primeiro** `/settings/invite`. Um `coach` que deveria ter acesso a `/settings/invite` (ADMIN_PROFESSOR_ROUTES) recebe `403`.
## Risco / Impacto

— Bug funcional: coaches são bloqueados de enviar convites, UI oferece o botão mas API/middleware retorna 403. Suporte recebe tickets "não consigo convidar".

## Correção proposta

— Verificar exceções **antes** do prefixo genérico:

```typescript
const isAdminProfessorRoute = ADMIN_PROFESSOR_ROUTES.some((r) => pathname.startsWith(r));
const isAdminOnlyRoute =
  !isAdminProfessorRoute &&
  ADMIN_ONLY_ROUTES.some((r) => pathname.startsWith(r));

if (isAdminProfessorRoute) {
  if (role !== "admin_master" && role !== "coach") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
} else if (isAdminOnlyRoute) {
  if (role !== "admin_master") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
}
```

Ou usar regex mais específico: `const ADMIN_ONLY_ROUTES = [/^\/settings$/, /^\/settings\/(?!invite).+/]`.

## Teste de regressão

— `middleware.test.ts`: user com role `coach` acessando `/settings/invite` → 200/allowed; acessando `/settings/general` → 403.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.1).