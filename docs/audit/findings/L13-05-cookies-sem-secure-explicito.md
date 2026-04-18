---
id: L13-05
audit_ref: "13.5"
lens: 13
title: "Cookies sem Secure explícito"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "middleware", "security-headers"]
files:
  - portal/src/lib/route-policy.ts
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
  Fixed in commit 6908546. New `portalCookieOptions()` helper in
  `route-policy.ts` returns a fully-typed `PortalCookieOptions` with
  `secure: process.env.NODE_ENV === "production"` (overridable via
  `overrideSecure` for local-HTTPS dev parity). All five cookie writes
  in `middleware.ts` (set portal_role, set portal_group_id, clear both
  on missing/legacy membership, and the multi-membership single-pick
  redirect) now go through this helper, eliminating the inline
  `{ path, httpOnly, sameSite, maxAge }` literals that lacked Secure.

  6 unit tests pin the contract: defaults (httpOnly+lax+path), maxAge
  defaults to the exported `PORTAL_COOKIE_MAX_AGE_SEC` (8 h), Secure
  flips with NODE_ENV (production/development/test), `maxAge: 0` is
  preserved (cookie clearing), and `overrideSecure` works in both
  directions.
---
# [L13-05] Cookies sem Secure explícito
> **Lente:** 13 — Middleware · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linhas 97-102, 125-136: `supabaseResponse.cookies.set(...)` sem `secure: true`. Em Vercel produção pode receber flag auto, mas **não em staging** com domínio customizado HTTP→HTTPS redirect.
## Risco / Impacto

— Cookie leak sobre HTTP em redirect intermediário (DNS poisoning MitM).

## Correção proposta

—

```typescript
const isProd = process.env.NODE_ENV === "production";
const cookieOpts = {
  path: "/",
  httpOnly: true,
  sameSite: "lax" as const,
  secure: isProd,
  maxAge: 60 * 60 * 8,
};
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.5).