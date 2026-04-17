---
id: L17-06
audit_ref: "17.6"
lens: 17
title: "csrfCheck não é chamado no middleware central"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "security-headers", "integration", "portal", "migration"]
files:
  - portal/src/lib/csrf.ts
  - portal/src/middleware.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L17-06] csrfCheck não é chamado no middleware central
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Existe `portal/src/lib/csrf.ts` mas `portal/src/middleware.ts` **não importa nem invoca**. Cada route handler deveria chamar individualmente — não encontrei uso.
## Risco / Impacto

— CSRF protection presente em código mas **inativa na produção**.

## Correção proposta

— Chamar no middleware **antes** de auth:

```typescript
// middleware.ts
import { csrfCheck } from "@/lib/csrf";

export async function middleware(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith("/api/") &&
      !["/api/custody/webhook", "/api/auth/callback"].includes(request.nextUrl.pathname)) {
    const csrfFail = csrfCheck(request);
    if (csrfFail) return csrfFail;
  }
  // ... rest
}
```

Exceções: webhooks (precisam receber POST sem origin), OAuth callback.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.6).