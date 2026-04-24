---
id: L07-01
audit_ref: "7.1"
lens: 7
title: "Mensagens de erro em português hardcoded no backend"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "i18n", "api", "testing"]
files:
  - portal/src/lib/api/error-messages.ts
  - portal/src/lib/api/error-messages.test.ts
  - portal/src/app/api/distribute-coins/route.ts
  - tools/audit/baselines/api-error-i18n-baseline.txt
correction_type: code
test_required: true
tests:
  - tools/audit/check-api-error-i18n.ts
  - portal/src/lib/api/error-messages.test.ts
linked_issues: []
linked_prs:
  - 1b768d4
owner: portal-platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Infraestrutura de i18n para erros HTTP canônicos. Três camadas:

  1. **Registry** — `portal/src/lib/api/error-messages.ts` mantém
     `ERROR_MESSAGES: Record<string, LocalisedMessage>` com 34 códigos
     canônicos cobrindo os 11 `COMMON_ERROR_CODES` + domínios
     (coin distribution, FX/swap, AI, paginação, training plans,
     gateway/DB/infra). Cada entrada tem triade obrigatória
     `{ en, ptBR, es }`. Inglês é a locale canônica do servidor
     (logs, Sentry, OpenAPI) — locales pt-BR e es ficam acessíveis
     via `resolveErrorMessage(code, locale)` para clientes que
     querem renderizar copy traduzida.

  2. **Locale resolver** — `resolveClientLocale(acceptLanguageHeader)`
     parseia `Accept-Language` para uma das três locales suportadas
     (`en` default, `ptBR` ou `es`). Tolera formatos `pt-BR`,
     `pt_BR`, `pt;q=0.8`, `es-MX`, `es-AR` etc.

  3. **CI guard** `tools/audit/check-api-error-i18n.ts` (`audit:api-error-i18n`):
     - valida shape do registry (~55 assertions)
     - obriga que todo código em `COMMON_ERROR_CODES` tenha entrada no registry
     - valida que toda entrada tem triade `en / ptBR / es`
     - **baseline ratchet**: grava `tools/audit/baselines/api-error-i18n-baseline.txt`
       (84 strings pt-BR legadas em rotas de API) como dívida técnica.
       Guard FALHA se: (a) nova string pt-BR aparece em `portal/src/app/api/**/*.ts`
       fora da whitelist de identificadores, ou (b) baseline tem entrada stale
       (arquivo já migrado) — sinalizando momento de encolher baseline via
       `UPDATE_BASELINE=1 npm run audit:api-error-i18n`.

  4. **Migração exemplar** — `portal/src/app/api/distribute-coins/route.ts`
     migrado para mensagens em inglês canônicas (`apiError(request,
     "ATHLETE_NOT_FOUND", ...)`, `"Coin distribution is temporarily
     suspended by ops."`, etc.). Demonstra padrão para as ~84 rotas
     restantes. Follow-up incremental: cada PR que toca uma rota
     remove sua string do baseline.

  Teste unitário `error-messages.test.ts` cobre (a) triade presente
  em todo código, (b) inglês ASCII-only (canônica server-side),
  (c) pt-BR tem diacríticos reais em ≥ 60 % dos códigos (sanidade
  de tradução), (d) SCREAMING_SNAKE, (e) `resolveErrorMessage`
  fallback para inglês, (f) `resolveClientLocale` reconhece pt/es/en
  variantes e faz fallback seguro para `en`.

  Coin policy: L07-01 não toca `coin_ledger` nem emite OmniCoins.
---
# [L07-01] Mensagens de erro em português hardcoded no backend
> **Lente:** 7 — CXO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Portal / Next.js API routes
**Personas impactadas:** Cliente mobile internacional (pt, en, es), parceiros B2B

## Achado
Rotas `/api/*` retornavam mensagens pt-BR cruas em `NextResponse.json({ error: "<string>" })`. App mobile (`omni_runner`) tem i18n completo (`app_localizations_en.dart`, `app_localizations_pt.dart`), mas ao bater na API recebia só pt-BR.

## Risco / Impacto
- Usuário de expansão internacional (EN / ES) vê mensagem em português → percepção de produto amador.
- Integrações B2B (assessorias que querem revender sob white-label em mercados latinos ou europeus) impossibilitadas de oferecer UX localizada sem patching no próprio app.
- Logs / Sentry / alertas ops em pt-BR → observability inconsistente em múltiplas regiões.

## Correção aplicada

### 1. Registry i18n canônico (`portal/src/lib/api/error-messages.ts`)
- `ERROR_MESSAGES: Record<string, LocalisedMessage>` com 34 códigos e triade `{ en, ptBR, es }`.
- Cobre todos os `COMMON_ERROR_CODES` (`UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `GONE`, `VALIDATION_FAILED`, `BAD_REQUEST`, `RATE_LIMITED`, `INTERNAL_ERROR`, `SERVICE_UNAVAILABLE`, `FEATURE_DISABLED`, `NO_GROUP_SESSION`) mais códigos de domínio (coin/custody, FX/swap, AI, training-plan).
- `resolveErrorMessage(code, locale)` retorna cópia localizada, fallback para inglês se código ou locale desconhecidos.
- `resolveClientLocale(acceptLanguageHeader)` parseia `Accept-Language` para `en | ptBR | es`.

### 2. CI guard (`tools/audit/check-api-error-i18n.ts`)
- ~55 asserts estáticos sobre forma do registry.
- Baseline ratchet: `tools/audit/baselines/api-error-i18n-baseline.txt` (84 entries) snapshota dívida pt-BR existente em rotas legacy. Guard falha se (a) **nova** string pt-BR entra fora do baseline, ou (b) entry do baseline ficou stale (sinal de migração concluída — hora de encolher baseline).
- `UPDATE_BASELINE=1` refresca baseline após migrações incrementais.

### 3. Migração piloto (`portal/src/app/api/distribute-coins/route.ts`)
- 4 strings pt-BR substituídas por mensagens inglesas canônicas usando `apiError(..., "ATHLETE_NOT_FOUND", ...)` e `errorBody("CUSTODY_FAILED", "Insufficient custody backing. ...")`.
- Demonstra padrão para outras rotas migrarem incrementalmente.

### 4. Teste unitário (`portal/src/lib/api/error-messages.test.ts`)
- Registry shape (triade obrigatória, inglês ASCII-only, SCREAMING_SNAKE, cobertura de `COMMON_ERROR_CODES`).
- `resolveErrorMessage` defaults + fallback.
- `resolveClientLocale` (pt, pt-BR, pt_BR, pt;q=0.8, es, es-MX, en, en-US, zz-ZZ).

## Teste de regressão
- `npm run audit:api-error-i18n` — 67 asserts, incluindo que nenhuma string pt-BR nova entre no repositório.
- `npm run -s test -- portal/src/lib/api/error-messages` — ~14 casos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.1).
- `2026-04-21` — Registry i18n + CI guard (ratchet) + migração piloto (`distribute-coins`). Baseline de 84 strings pt-BR legacy congelado como dívida técnica para migração incremental.
