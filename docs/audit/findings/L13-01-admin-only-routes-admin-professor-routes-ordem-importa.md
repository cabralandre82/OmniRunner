---
id: L13-01
audit_ref: "13.1"
lens: 13
title: "ADMIN_ONLY_ROUTES + ADMIN_PROFESSOR_ROUTES — ordem importa, e está errada"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "testing"]
files:
  - portal/src/middleware.ts
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