---
id: L13-09
audit_ref: "13.9"
lens: 13
title: "Middleware redirect chain em single-membership causa duplo round-trip"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-21
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "ux", "perf", "fixed"]
files:
  - portal/src/middleware.ts
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: true
tests:
  - "npm run audit:k3-domain-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — single-membership branch now sets portal_group_id and
  portal_role on the SAME response (supabaseResponse) and falls
  through to role-gated handling. Eliminates the 200 ms cost of the
  redirect-then-replay round-trip on first-touch. Next.js 14.2+
  propagates middleware-set cookies to downstream RSCs/route handlers
  within the same navigation, so the request continues to its
  intended pathname with the cookies in place.
---
# [L13-09] Middleware redirect chain em single-membership causa duplo round-trip
> **Lente:** 13 — Middleware · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linhas 124-137: cria redirect set-cookie, browser vai, middleware roda de novo, agora encontra cookie. Dois requests para um primeiro acesso. UX: 200 ms extra.
## Correção proposta

— Set cookie no **mesmo response** + let RSC ler via `cookies()` imediatamente (cookies set no middleware response propagam ao RSC da mesma navigation em Next.js 14+). Eliminar redirect:

```typescript
supabaseResponse.cookies.set("portal_group_id", groupId, cookieOpts);
supabaseResponse.cookies.set("portal_role", role, cookieOpts);
return supabaseResponse;  // no redirect
```

Verificar se Next 14.2.x entrega cookie na mesma navigation.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.9).