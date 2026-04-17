---
id: L13-07
audit_ref: "13.7"
lens: 13
title: "PUBLIC_ROUTES contém /api/custody/webhook sem IP allow-list"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "security-headers", "portal"]
files: []
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
# [L13-07] PUBLIC_ROUTES contém /api/custody/webhook sem IP allow-list
> **Lente:** 13 — Middleware · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linha 4: webhook exposto em endpoint público. Relacionado a [1.17] — MP webhook não tem HMAC.
## Correção proposta

— Middleware checar `request.ip` contra allow-list configurada por gateway:

```typescript
if (pathname === "/api/custody/webhook") {
  const ip = request.ip ?? request.headers.get("x-forwarded-for")?.split(",")[0];
  if (!PAYMENT_GATEWAY_IPS.includes(ip)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
}
```

Lista mantida em env: Stripe publica ranges; MP publica em doc.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.7).