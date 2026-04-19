---
id: L01-38
audit_ref: "1.38"
lens: 1
title: "CSP 'unsafe-inline' + 'unsafe-eval' em script-src"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["security-headers", "portal", "observability", "xss", "csp"]
files:
  - portal/src/lib/security/csp.ts
  - portal/src/lib/security/csp.test.ts
  - portal/src/middleware.ts
  - portal/next.config.mjs
  - portal/src/app/api/docs/route.ts
  - portal/src/app/api/docs/route.test.ts
  - portal/scripts/swagger-init.js
  - portal/scripts/copy-swagger-ui.mjs
  - portal/src/test/setup.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/security/csp.test.ts
  - portal/src/app/api/csp-report/route.test.ts
  - portal/src/app/api/docs/route.test.ts
linked_issues: []
linked_prs: ["c41fef7"]
owner: portal-team
runbook: docs/runbooks/CSP_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Defesa em três camadas substituiu o CSP estático fraco por uma
  política nonce-based moderna sem nenhum `'unsafe-inline'` ou
  `'unsafe-eval'` em `script-src` na produção:

  1. **Builder puro** (`portal/src/lib/security/csp.ts`) —
     `buildCsp({ nonce, isDev, reportEndpoint })` é a única fonte da
     verdade do header. Assertions positivas + negativas em
     `csp.test.ts` (24 casos) garantem que produção nunca volte a
     carregar `'unsafe-inline'` / `'unsafe-eval'`. Em dev, apenas
     `'unsafe-eval'` é re-adicionado (Next.js Fast Refresh / React
     Refresh dependem dele); o nonce continua presente em ambos os
     ambientes. `style-src 'unsafe-inline'` é mantido por decisão
     explícita (Tailwind/shadcn/next-font emitem `<style>` inline e
     XSS via inline-CSS é primitivo de exfiltração muito mais
     fraco que via inline-JS — trade-off documentado no JSDoc).

  2. **Middleware per-request nonce** (`portal/src/middleware.ts`) —
     `generateNonce()` produz 16 bytes de CSPRNG por request,
     propagados via `x-nonce` no header da request downstream (RSCs
     leem com `headers().get("x-nonce")` para emitir
     `<Script nonce={…}>`) e no header de response. `tagResponse`
     garante que o CSP acompanha TODA resposta — incluindo
     redirects, JSON error envelopes e 403 — então páginas de erro
     (que historicamente são as mais XSS-prone) não escapam à
     política. CSP estático em `next.config.mjs` foi removido
     (middleware é a fonte única).

  3. **Sink de violações** (`portal/src/app/api/csp-report/route.ts`,
     L10-05) — endpoint público (`PUBLIC_ROUTES`) que aceita as
     duas formas de payload (`report-uri` legado +
     `report-to`/`reports+json` moderno do Chromium), normaliza
     campos, classifica severidade (`script-src*` → warn + Sentry
     `captureMessage`; resto → info-only) e protege o pipeline com
     cap de 8 KiB de body + rate limit per-process de 60 reports /
     60 s. 13 testes cobrem parser, severidade e proteções.

  Migração de inline `<script>`:
    - `app/api/docs` era o único lugar com `<script>…body…</script>`
      no portal (bootstrap do Swagger-UI). Externalizado para
      `scripts/swagger-init.js` (tracked) e copiado para
      `public/vendor/swagger-ui/swagger-init.js` no build via
      `copy-swagger-ui.mjs`. O HTML agora só carrega
      `<script src="…"></script>`, totalmente coberto por
      `script-src 'self'` sem precisar de relaxamento.
    - Test `route.test.ts` tem invariante negativa
      (`<script\b(?![^>]*\bsrc=)[^>]*>`) que falha se algum
      contributor reintroduzir inline script no futuro.

  Decisões de escopo deliberadas:
    - `style-src 'unsafe-inline'` — mantido (ver acima). Migração
      tracked separadamente.
    - `'strict-dynamic'` adotado: chunks dinâmicos do Next.js
      (lazy-loaded routes) carregam sem precisar de allow-list por
      hash.
    - `connect-src https://*.sentry.io` mantido como fallback
      defensivo: o `tunnelRoute: "/monitoring"` proxy para Sentry,
      mas se a tunnel falhar a SDK volta para ingest direto.
    - Fallback de entropia em test env: `globalThis.crypto` não é
      auto-populado em Node 18 ESM (vitest 2 default). Polyfill em
      `src/test/setup.ts` ponteia para `node:crypto.webcrypto`.
      Edge runtime e Node 19+ usam `globalThis.crypto` nativo —
      `csp.ts` não carrega `node:crypto` estaticamente para
      preservar compatibilidade Edge.
---
# [L01-38] CSP 'unsafe-inline' + 'unsafe-eval' em script-src
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** PORTAL
**Personas impactadas:** Todos
## Achado original
`portal/next.config.mjs:78-79`: `"script-src 'self' 'unsafe-inline' 'unsafe-eval' https://*.sentry.io"`. Isso **anula proteção XSS do CSP**. Qualquer injeção de HTML com `<script>inline</script>` ou `<div onerror=...>` executa.

## Risco / Impacto

XSS leva a full account takeover — acesso aos cookies `portal_group_id` é httpOnly, mas atacante pode fazer requests autenticados no mesmo domínio (sameSite:lax permite via tag navigation).

## Correção aplicada

Builder puro + middleware per-request nonce + sink de violações; veja `note` no frontmatter para o trace completo.

`script-src` em produção: `'self' 'nonce-<base64>' 'strict-dynamic'` — sem `'unsafe-inline'`, sem `'unsafe-eval'`. Bootstrap do Swagger-UI externalizado. CSP estático removido de `next.config.mjs` (middleware é fonte única).

Cobertura de testes:
- `portal/src/lib/security/csp.test.ts` (24): builder puro, asserções positivas e negativas.
- `portal/src/app/api/csp-report/route.test.ts` (13): sink de violações.
- `portal/src/app/api/docs/route.test.ts` (5): invariante negativa para inline script.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.38]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.38).
- `2026-04-17` — Corrigido em `c41fef7`. CSP movido para middleware com nonce per-request + `strict-dynamic`. Inline `<script>` do Swagger UI externalizado. Sink `/api/csp-report` adicionado (L10-05 fechado em conjunto). Runbook em `docs/runbooks/CSP_RUNBOOK.md`. 1217 testes passando.
