---
id: L13-07
audit_ref: "13.7"
lens: 13
title: "PUBLIC_ROUTES contém /api/custody/webhook sem IP allow-list"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "webhook", "security-headers", "portal", "middleware"]
files:
  - portal/src/lib/webhook-ip-allowlist.ts
  - portal/src/middleware.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/webhook-ip-allowlist.test.ts
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
  Fixed in commit 6908546. New module
  `portal/src/lib/webhook-ip-allowlist.ts` implements an opt-in IP
  allow-list controlled by env `PAYMENT_GATEWAY_IPS_ALLOWLIST` (CSV of
  literal IPv4/IPv6 or v4 CIDR ranges). The middleware calls
  `enforceWebhookIpAllowlist()` for `/api/custody/webhook` BEFORE any
  auth/session work; mismatch returns a tagged 403, otherwise the
  request continues into the existing HMAC-verifying route handler.

  Defence-in-depth posture: when the env var is unset, the module
  passes through (HMAC at the route handler is already the primary
  defence) and logs a single warning per process in production. We
  deliberately do NOT fail-closed on missing config — that would turn
  an env-var typo into a payments incident.

  24 unit tests cover: parsing (literal v4, CIDR, IPv6 case-insensitive,
  malformed entries dropped), CIDR network/mask math (incl. /0 and /32
  edges), match algorithm (literal, CIDR, IPv6 canonical form, mixed v4
  allow-list vs v6 request), source-IP extraction (`request.ip` >
  `x-forwarded-for[0]` > `x-real-ip`, with port stripping for both v4
  and bracketed v6), and `enforceWebhookIpAllowlist` end-to-end
  (unset → null, empty → null, no-match → 403, CIDR/literal/XFF match
  → null, no-IP → 403).
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