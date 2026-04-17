---
id: L01-38
audit_ref: "1.38"
lens: 1
title: "CSP 'unsafe-inline' + 'unsafe-eval' em script-src"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["security-headers", "portal", "observability"]
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
# [L01-38] CSP 'unsafe-inline' + 'unsafe-eval' em script-src
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Todos
## Achado
`portal/next.config.mjs:78-79`: `"script-src 'self' 'unsafe-inline' 'unsafe-eval' https://*.sentry.io"`. Isso **anula proteção XSS do CSP**. Qualquer injeção de HTML com `<script>inline</script>` ou `<div onerror=...>` executa.
## Risco / Impacto

XSS leva a full account takeover — acesso aos cookies `portal_group_id` é httpOnly, mas atacante pode fazer requests autenticados no mesmo domínio (sameSite:lax permite via tag navigation).

## Correção proposta

Remover `'unsafe-inline'` e `'unsafe-eval'`. Next.js 14+ suporta nonces via `next.config.mjs` + `headers()` + middleware. Ou migrar inline scripts para Server Components / arquivos estáticos. Para Framer Motion e shadcn, geralmente não precisa unsafe-inline (só usa inline styles, não scripts).
  ```javascript
  // next.config.mjs
  "script-src 'self' 'nonce-{NONCE}' 'strict-dynamic' https://*.sentry.io"
  ```
  Gerar nonce no middleware e passar via header `x-nonce`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.38]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.38).