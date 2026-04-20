---
id: L17-06
audit_ref: "17.6"
lens: 17
title: "csrfCheck não é chamado no middleware central"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-20
tags: ["finance", "webhook", "security-headers", "integration", "portal", "middleware"]
files:
  - portal/src/lib/api/csrf.ts
  - portal/src/middleware.ts
  - docs/runbooks/CSRF_RUNBOOK.md
correction_type: process
test_required: true
tests:
  - portal/src/lib/api/csrf.test.ts
linked_issues: []
linked_prs: ["c415f82"]
owner: platform
runbook: docs/runbooks/CSRF_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido com **dois ganhos** sobrepostos sobre L01-06 (que já tinha
  feito o token double-submit em `lib/api/csrf.ts` e o wire em
  middleware para o allow-list financeiro):

  1. **Origin pinning default-deny (novo)** em
     `portal/src/lib/api/csrf.ts`:
     - `shouldEnforceOrigin(method, path)` — retorna `true` para
       qualquer `(POST|PUT|PATCH|DELETE)` em `/api/*` que NÃO esteja
       em `CSRF_EXEMPT_PREFIXES`.
     - `verifyOrigin(req)` — exige `Origin` (ou fallback `Referer`)
       cujo host bata exatamente com o `Host` da requisição. Rejeita
       `Origin: null` (sandbox iframes / `file://`), Origin
       malformado, e ausência simultânea de `Origin` + `Referer`.
     - Wired em `portal/src/middleware.ts` ANTES do token gate e
       ANTES da auth: chamada pura, ~5 µs, nega tráfego de atacante
       sem Postgres round-trip.
     - `CSRF_EXEMPT_PREFIXES` ampliado com justificativa por entrada
       para incluir `/api/csp-report` (browsers enviam
       `Origin: null`), `/api/liveness`, `/api/health` (probes
       externos sem cookie).
     - Métricas: `csrf.origin_blocked{reason=...}` por sub-código
       para discernir spike pós-deploy (rota nova esquecida) vs
       attack pattern (mesmo IP).

  2. **Limpeza do código morto**:
     - Deletados `portal/src/lib/csrf.ts` (origin/referer simples,
       nunca foi importado por middleware) e
     `portal/src/lib/csrf.test.ts`. Single source of truth: tudo
       vive em `lib/api/csrf.ts`.

  3. **Runbook atualizado**:
     - `docs/runbooks/CSRF_RUNBOOK.md` reescrito com o novo gate
       de Origin (§§ 1.0, 2.1, 3.0, 4.0, 6.0) e tabela de
       sub-códigos `ORIGIN_*` para triagem.
     - `docs/runbooks/README.md` indexa o runbook sob "Portal
       security headers".

  Verification:
  - `npx vitest run` — 1378 testes verdes (36 em `csrf.test.ts`,
    cobrindo `shouldEnforceOrigin`, `verifyOrigin` em todas as
    branches, e regressão de todos os helpers de L01-06).
  - `npm run lint` — limpo.
  - `tsc --noEmit` — sem erros novos (o erro pré-existente em
    `lib/feature-flags.ts:69` segue tracked separadamente).
  - `tools/audit/verify.ts` — 348 findings validados.

  **Backwards compatibility**: nenhum cliente quebra. Todos os
  `fetch()` do portal já enviam `Origin` automaticamente (browser
  default em POST). O Flutter app (`omni_runner`) chama Supabase
  direto, não `/api/*` do portal — confirmado em
  `omni_runner/lib/core/config/app_config.dart`.
---
# [L17-06] csrfCheck não é chamado no middleware central
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Existe `portal/src/lib/csrf.ts` mas `portal/src/middleware.ts` **não importa nem invoca**. Cada route handler deveria chamar individualmente — não encontrei uso.
## Risco / Impacto
— CSRF protection presente em código mas **inativa na produção**.
## Correção aplicada
Ver `note:` no frontmatter para o resumo executivo, e
`docs/runbooks/CSRF_RUNBOOK.md` (§§ 1.0, 2.1, 3.0, 4.0, 6.0) para
o detalhamento operacional dos dois gates (Origin pinning + Token
double-submit) que agora compõem a defesa CSRF do portal.
## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.6).
- `2026-04-20` — **Fixed.** Optei por defesa-em-profundidade em vez de migrar todos
  os `fetch()` do portal para `csrfFetch` em uma só PR (que seria invasivo e
  arriscado). Origin pinning default-on cobre TODA a superfície mutante de
  `/api/*` sem mudança de cliente; o token gate continua opt-in via
  `CSRF_PROTECTED_PREFIXES` para rotas financeiras (defesa-em-profundidade).
  Código morto `lib/csrf.ts` removido — single source of truth em
  `lib/api/csrf.ts`. L01-06 e L17-06 agora compõem uma única política
  documentada em `CSRF_RUNBOOK.md`.