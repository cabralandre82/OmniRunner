---
id: L13-09
audit_ref: "13.9"
lens: 13
title: "Middleware redirect chain em single-membership causa duplo round-trip"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal", "ux"]
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