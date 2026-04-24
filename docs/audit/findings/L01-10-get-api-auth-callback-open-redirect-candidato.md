---
id: L01-10
audit_ref: "1.10"
lens: 1
title: "GET /api/auth/callback — Open redirect candidato"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["integration", "mobile", "portal", "testing", "open-redirect", "fixed"]
files:
  - portal/src/app/api/auth/callback/route.ts
  - portal/src/lib/security/safe-next.ts
  - portal/src/lib/security/safe-next.test.ts
  - tools/audit/check-k4-security-fixes.ts
correction_type: code
test_required: true
tests:
  - "portal/src/lib/security/safe-next.test.ts (8 vitest cases)"
  - "npm run audit:k4-security-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — pure-domain safeNext() module rejects:
    • protocol-relative paths (`//evil.example.com/x`)
    • Windows-style backslash escape (`/\evil.example.com/x`)
    • foreign schemes (`javascript:`, `data:`, `https://`)
    • paths longer than 256 chars
    • characters outside ASCII alphanumeric + `-_./?&=%`
  The OAuth callback now consumes searchParams.get("next") through
  safeNext() and falls back to /dashboard on validation failure.
  Cannot redirect to /platform/* via crafted URL anymore.
---
# [L01-10] GET /api/auth/callback — Open redirect candidato
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Qualquer usuário após OAuth
## Achado
`portal/src/app/api/auth/callback/route.ts:9` aceita `next` do query e redireciona para `${origin}${next}`. O pattern `origin + path` impede redirect cross-origin clássico, mas permite `next=/select-group` ou `next=/platform` — se o atacante conseguir forçar um callback, o redirect pós-login vai para uma tela sensível. Também: `next` pode ser muito longo e sem validação de schema.
## Risco / Impacto

Phishing por redirect forçado a path interno controlado (ex: `/platform/assessorias/create?seed=...`). Limitado porque é same-origin.

## Correção proposta

```typescript
  const ALLOWED_NEXT = /^\/[a-z0-9\-_/]+$/i;
  const next = searchParams.get("next") ?? "/dashboard";
  const safeNext = ALLOWED_NEXT.test(next) && !next.startsWith("//") ? next : "/dashboard";
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.10).