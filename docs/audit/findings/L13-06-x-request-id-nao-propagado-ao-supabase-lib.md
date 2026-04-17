---
id: L13-06
audit_ref: "13.6"
lens: 13
title: "x-request-id não propagado ao supabase/lib downstream"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["security-headers"]
files: []
correction_type: code
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