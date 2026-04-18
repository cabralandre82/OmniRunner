---
id: L13-06
audit_ref: "13.6"
lens: 13
title: "x-request-id não propagado ao supabase/lib downstream"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["security-headers", "portal", "middleware", "observability"]
files:
  - portal/src/lib/supabase/middleware.ts
  - portal/src/middleware.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/route-policy.test.ts
linked_issues: []
linked_prs:
  - "6908546"
owner: platform
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in commit 6908546. `lib/supabase/middleware.ts:updateSession`
  now accepts an optional `extraRequestHeaders` map and threads it
  through `NextResponse.next({ request: { headers: requestHeaders } })`,
  so the value reaches downstream RSCs and route handlers via
  `headers().get("x-request-id")` — not just the response headers as
  before.

  `middleware.ts` computes the request id once (`request.headers.get
  ("x-request-id") ?? crypto.randomUUID()`) at the very top, passes
  `{ "x-request-id": requestId }` into every `updateSession()` call
  (public, auth-only, auth-no-group, and the staff branch), and tags
  every response (including 403 JSON, redirects, and `tagResponse`
  helper-wrapped error paths) with the same id. Existing observability
  pipelines that already index this header now see end-to-end
  request-id continuity from edge → middleware → RSC → Supabase.
---
# [L13-06] x-request-id não propagado ao supabase/lib downstream
> **Lente:** 13 — Middleware · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linhas 161-162 setam no `supabaseResponse.headers` (resposta). Mas o header **não é injetado no `request`** — RSCs e API handlers fazendo `createServerClient()` não têm acesso ao request-id.
## Correção proposta

—

```typescript
const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
const requestHeaders = new Headers(request.headers);
requestHeaders.set("x-request-id", requestId);

const response = NextResponse.next({ request: { headers: requestHeaders } });
response.headers.set("x-request-id", requestId);
```

Depois RSC lê via `headers().get("x-request-id")`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.6).