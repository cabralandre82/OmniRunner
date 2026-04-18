---
id: L14-03
audit_ref: "14.3"
lens: 14
title: "/api/docs carrega Swagger-UI de unpkg sem SRI"
severity: critical
status: fixed
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "supply-chain"]
files:
  - portal/src/app/api/docs/route.ts
  - portal/src/app/api/docs/route.test.ts
  - portal/scripts/copy-swagger-ui.mjs
  - portal/package.json
  - portal/.gitignore
correction_type: code
test_required: true
tests:
  - portal/src/app/api/docs/route.test.ts
linked_issues: []
linked_prs:
  - "commit:e313c5c"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L14-03] /api/docs carrega Swagger-UI de unpkg sem SRI
> **Lente:** 14 — Contracts · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟢 fixed
**Camada:** portal (supply chain)
**Personas impactadas:** admin_master, platform_admin (usuários autenticados que acessam /api/docs)

## Achado
`portal/src/app/api/docs/route.ts` retornava HTML que carregava 3 recursos de
`https://unpkg.com/swagger-ui-dist@5.11.0/` (CSS + 2 bundles JS) **sem `integrity`
nem versionamento imutável**. Um comprometimento do unpkg (DNS hijack, account
takeover do mantenedor, RCE em edge da CDN, ou ataque BGP) permitiria injetar JS
arbitrário no navegador de admins autenticados que abrem a doc da API.

Trechos originais:
```29:30:portal/src/app/api/docs/route.ts
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js" crossorigin></script>
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-standalone-preset.js" crossorigin></script>
```

**Blast radius:** Apesar de `/api/docs` estar atrás de autenticação (middleware
em `portal/src/middleware.ts` não inclui `/api/docs` no `PUBLIC_ROUTES`), o
impacto é agravado: apenas usuários com privilégios elevados (platform_admin,
admin_master) tipicamente abrem a documentação da API. Um payload malicioso
executa com a sessão ativa desses usuários (CSRF, roubo de cookies/JWT, ações em
nome do usuário).

## Correção implementada

**1. Self-host dos assets** (em vez de SRI em URL externa):
- Adicionada dependência `swagger-ui-dist@5.11.0` em `portal/package.json`.
- Script `portal/scripts/copy-swagger-ui.mjs` copia 5 assets de
  `node_modules/swagger-ui-dist/` para `portal/public/vendor/swagger-ui/`:
  `swagger-ui.css`, `swagger-ui-bundle.js`, `swagger-ui-standalone-preset.js`,
  `favicon-{16,32}x{16,32}.png`.
- Gera `manifest.json` com SHA-384 de cada asset para auditoria/CI.
- Hooks: `postinstall`, `prebuild`, `predev` garantem que os arquivos existam
  em qualquer ambiente (dev local, CI, Vercel, Docker).
- `.gitignore` exclui `/public/vendor/swagger-ui/` (artefato gerado).

**2. HTML refatorado** (`portal/src/app/api/docs/route.ts`):
- Todas as referências a `unpkg.com` removidas — substituídas por caminhos
  same-origin `/vendor/swagger-ui/*`.
- Removido `crossorigin` (não é mais necessário, same-origin).
- Adicionados headers defensivos: `Cache-Control: no-store`,
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`.
- Adicionados favicons same-origin (substitui o default que o Swagger tentaria
  buscar em `/favicon-32x32.png`).

**3. Testes** (`portal/src/app/api/docs/route.test.ts`, 5 casos):
- ✅ 200 OK com headers defensivos corretos.
- ✅ **Invariante crítica: nenhuma URL absoluta http(s)** no HTML —
  regex `(src|href)=\s*["']https?://` não pode casar.
- ✅ Lista explícita de CDNs proibidos (unpkg, jsdelivr, cdnjs, googleapis, gstatic,
  bootstrapcdn) não aparece no HTML.
- ✅ Referencia `/vendor/swagger-ui/*` para os 3 assets principais.
- ✅ Não expõe secrets inline (JWT, `sk_live_*`, `service_role`).

### Propriedades garantidas
- Supply chain externo zerado para Swagger-UI: builds reproduzíveis, hash
  auditável em `manifest.json`.
- Mesmo que `unpkg.com` seja comprometido no futuro, `/api/docs` continua
  seguro — não faz network calls externos.
- Bumps de versão exigem mudança explícita em `package.json` (review obrigatório),
  nenhum floating tag.
- Teste de regressão garante que ninguém reintroduza URL externa acidentalmente.

### O que ainda falta
- [ ] Adicionar CSP header para /api/docs (`script-src 'self' 'unsafe-inline';
  connect-src 'self'; img-src 'self' data:;`) — bloqueio profundo. Tracking via
  finding L01-40 (CSP global). Não é blocker desta correção.
- [ ] Monitorar `swagger-ui-dist` em Dependabot/Renovate para aplicar updates
  de segurança. Tracking em L16-xx (supply chain / Dependabot).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/07-qa-dx.md`](../parts/07-qa-dx.md) — anchor `[14.3]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.3).
- `2026-04-17` — Correção implementada: self-host Swagger-UI, remove dependência de unpkg, 5 testes de regressão.
- `2026-04-17` — E2E green (`tools/validate-migrations.sh --run-tests` 165/165 + 146/146; testes da rota docs em `route.test.ts`). Promovido a `fixed` (commit `e313c5c`).
