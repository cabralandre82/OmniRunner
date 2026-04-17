---
id: L13-05
audit_ref: "13.5"
lens: 13
title: "Cookies sem Secure explícito"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: []
files: []
correction_type: config
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