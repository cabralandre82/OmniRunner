---
id: L17-01
audit_ref: "17.1"
lens: 17
title: "withErrorHandler não é usado em endpoints financeiros críticos"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "mobile", "portal", "observability", "testing", "reliability"]
files:
  - portal/src/lib/api-handler.ts
  - portal/src/lib/api-handler.test.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/app/api/custody/route.ts
  - portal/src/app/api/custody/webhook/route.ts
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/custody/fx-quote/route.ts
  - portal/src/app/api/distribute-coins/route.ts
  - portal/src/app/api/clearing/route.ts
  - portal/src/app/api/cron/settle-clearing-batch/route.ts
  - portal/src/app/api/checkout/route.ts
  - portal/src/app/api/billing/asaas/route.ts
  - portal/src/app/api/billing/batch/route.ts
  - portal/src/app/api/billing-portal/route.ts
  - portal/src/app/api/auto-topup/route.ts
  - portal/src/app/api/financial/plans/route.ts
  - portal/src/app/api/financial/subscriptions/route.ts
  - portal/src/app/api/gateway-preference/route.ts
  - portal/src/app/api/export/financial/route.ts
  - portal/src/app/api/platform/refunds/route.ts
  - portal/src/app/api/platform/products/route.ts
  - portal/src/app/api/platform/fees/route.ts
  - portal/src/app/api/platform/feature-flags/route.ts
  - portal/src/app/api/platform/assessorias/route.ts
  - portal/src/app/api/platform/support/route.ts
  - portal/src/app/api/platform/liga/route.ts
  - portal/src/app/api/platform/health/route.ts
  - portal/src/app/api/platform/cron-health/route.ts
  - portal/src/app/api/platform/cron-sla/route.ts
  - portal/src/app/api/platform/invariants/route.ts
  - portal/src/app/api/platform/invariants/wallets/route.ts
  - portal/src/app/api/platform/invariants/enforce/route.ts
  - portal/src/app/api/platform/custody/withdrawals/[id]/complete/route.ts
  - portal/src/app/api/platform/custody/withdrawals/[id]/fail/route.ts
  - tools/check_financial_routes_have_error_handler.ts
  - docs/runbooks/API_ERROR_HANDLING_RUNBOOK.md
correction_type: process
test_required: true
tests:
  - portal/src/lib/api-handler.test.ts
  - tools/check_financial_routes_have_error_handler.ts
linked_issues: []
linked_prs:
  - "26245a8"
owner: platform-team
runbook: docs/runbooks/API_ERROR_HANDLING_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Wrapper hardened (Sentry span tags + canonical 500 envelope + always-on
  request_id). 37 financial/platform routes wrapped. CI guard
  `tools/check_financial_routes_have_error_handler.ts` passes with 0
  critical fails (31 non-financial routes still flagged as `info` —
  follow-up tracked separately).
---
# [L17-01] withErrorHandler não é usado em endpoints financeiros críticos
> **Lente:** 17 — VP Eng · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed (2026-04-17)
**Camada:** portal/api · **Runbook:** [`docs/runbooks/API_ERROR_HANDLING_RUNBOOK.md`](../../runbooks/API_ERROR_HANDLING_RUNBOOK.md)
**Personas impactadas:** todas as personas com mutações financeiras (atleta-pagante, treinador, admin assessoria, platform admin).

## Achado
`portal/src/lib/api-handler.ts:10-30` expunha `withErrorHandler(handler, routeName)` mas **nenhuma** rota financeira (`/api/custody`, `/api/swap`, `/api/distribute-coins`, `/api/custody/withdraw`, etc.) usava o wrapper. Cada endpoint mantinha seu próprio `try/catch` inconsistente — alguns vazavam `String(e)` ou `error.message` direto, outros não capturavam o trecho problemático e perdiam o evento no Sentry, e nenhum garantia propagação de `x-request-id` na resposta de erro (ver [14.5] para o envelope canônico e [13.6] para tracing).

## Risco / Impacto

- **Disclosure**: stack traces, mensagens de driver Postgres (`PrismaClientKnownRequestError: ...`), nomes de tabela e queries SQL chegavam ao cliente em alguns endpoints — material útil para reconnaissance.
- **Observabilidade quebrada**: throws fora dos `try` não chegavam ao Sentry; debugging de incidente financeiro dependia de ler logs do Vercel um por um.
- **Sem rastreabilidade**: `x-request-id` enviado pelo Flutter app/parceiros B2B não voltava em payloads de erro → impossível correlacionar bug-report do usuário com Sentry.
- **i18n drift**: mensagens hardcoded em pt-BR (`"Não autenticado"`, `"Falha ao processar"`) ([7.1]) — partner B2B em inglês via mensagens incompreensíveis.
- **Inconsistência de envelope**: alguns endpoints retornavam `{ error: "..." }`, outros `{ ok: false, error: { code, message } }`, outros `{ message: "..." }` — quebra de contrato com clientes ([14.5]).

## Correção aplicada

### 1. Endurecimento do wrapper (`portal/src/lib/api-handler.ts`)

`withErrorHandler` agora:
- Resolve `x-request-id` (vindo do header ou gerado via `crypto.randomUUID()`) e o ecoa **tanto no header quanto no `error.request_id`** do envelope canônico.
- Tagueia o span ativo do Sentry com `omni.route` + `http.method` (via `Sentry.getActiveSpan()`), permitindo filtros precisos no Sentry UI.
- Converte qualquer throw em `apiError(req, "INTERNAL_ERROR", fallbackMessage, 500, { requestId })` — envelope canônico definido em [14.5].
- Aceita `routeArgs: any[]` para forwardar context dinâmico do Next.js (`{ params }`).
- Suporta um `errorMap?: (err, req) => NextResponse | null` opcional para handlers wrappear erros de domínio (e.g. `SwapError`, `FxQuoteError`) com status codes específicos antes do fallback 500.
- Suporta `fallbackMessage?: string` opcional para customizar a mensagem do 500 genérico.

### 2. Wrappeamento sistemático (37 rotas financeiras / platform-admin)

Toda rota em `portal/src/app/api/**` com risco financeiro foi convertida do padrão antigo `export async function POST(...)` para `export const POST = withErrorHandler(_post, "api.<group>.<verb>")`. Os endpoints chamados explicitamente no achado original — `/api/custody`, `/api/swap`, `/api/distribute-coins`, `/api/custody/withdraw` — foram tratados primeiro, junto com a sua família estendida (clearing, checkout, billing, billing-portal, auto-topup, financial/plans, financial/subscriptions, gateway-preference, export/financial) e o cluster `platform/*` (refunds, products, fees, feature-flags, assessorias, support, liga, health, cron-health, cron-sla, invariants, invariants/wallets, invariants/enforce, custody/withdrawals/[id]/complete, custody/withdrawals/[id]/fail). As rotas `v1/*` herdam a proteção via `wrapV1Handler` (que delega para o handler legado já wrappeado).

Os `try/catch` triviais que apenas reformatavam o erro foram **removidos** — agora delegam para o wrapper. `try/catch` foram mantidos apenas onde ainda fazem trabalho útil (mapeamento de erros conhecidos para HTTP codes específicos, e.g. `PGRST/does not exist` → 503 em routes ainda em rollout).

### 3. Testes (`portal/src/lib/api-handler.test.ts`)

Suite nova com 11 testes cobrindo:
- Execução bem-sucedida do handler (passthrough);
- Throw genérico → 500 INTERNAL_ERROR canônico;
- Geração automática de `x-request-id` quando ausente;
- Propagação de `x-request-id` quando presente no request;
- Forward de context dinâmico do Next.js (`{ params }`);
- `errorMap` mapeando erro específico, fall-through quando `errorMap` retorna `null`, recuperação quando `errorMap` lança.

Testes pré-existentes das rotas afetadas (custody, swap, fx-quote, billing-portal, financial, gateway-preference, platform/health, platform/fees, platform/invariants) foram atualizados para passar `NextRequest` explicitamente ao GET wrappeado e assertar o novo envelope canônico em casos de throw inesperado.

### 4. CI guard (`tools/check_financial_routes_have_error_handler.ts`)

Script standalone (sem dependências externas além de `node:fs`/`tsx`) que percorre `portal/src/app/api/**/route.ts` e:
- Identifica rotas **financeiras / platform-admin** via `FINANCIAL_ROUTE_PATTERNS` (lista positiva).
- Aceita três formas de export válidas: `withErrorHandler(...)` direto, `wrapV1Handler(...)` (alias v1), ou export const com import explícito de `withErrorHandler` (cobre `const handler = withErrorHandler(...); export const POST = handler`).
- Falha CI (`exit 1`) apenas se uma rota **financeira** estiver desprotegida; rotas não-financeiras são reportadas como `info` mas não bloqueiam (o universalização é tracking pra follow-up).
- Modos: default (pretty), `--quiet` (só FAIL), `--json` (CI-friendly), `--strict` (também falha em info).

Resultado atual: `[L17-01] scanned 89 route file(s) (37 financial); 0 critical fail(s); 31 info; 0 exempt`.

### 5. Runbook (`docs/runbooks/API_ERROR_HANDLING_RUNBOOK.md`)

Novo runbook operacional cobrindo: como diagnosticar resposta não-canônica em produção, como rodar o CI guard, padrão de onboarding pra rotas novas (`_post` + `withErrorHandler` + helpers de `apiError/apiUnauthorized/...`), e os 5 anti-padrões mais comuns que o code review deve barrar.

## Teste de regressão

```bash
# Local + CI
npx tsx tools/check_financial_routes_have_error_handler.ts          # exit 0
npx tsx tools/check_financial_routes_have_error_handler.ts --quiet  # silent on success

# Vitest
cd portal && npx vitest run src/lib/api-handler.test.ts             # 11 tests pass
cd portal && npx vitest run src/app/api                              # 479 tests pass
```

## Follow-ups conhecidos

- **Universalizar o guard**: 31 rotas não-financeiras (`/api/announcements`, `/api/workouts/*`, `/api/training-plan/*`, etc.) ainda usam `export async function`. Não bloqueia L17-01 mas é coberto por novo finding (a abrir) que estenderá `FINANCIAL_ROUTE_PATTERNS` ou flippa o guard pra `--strict` por padrão.
- **ESLint rule**: a auditoria sugeria criar `eslint-plugin-custom-omni`. O CI guard via `tsx` cobre o mesmo objetivo com menor superfície (sem novo plugin pra manter); ESLint rule fica como nice-to-have se quisermos feedback in-IDE.
- **i18n** ([7.1]): mensagens pt-BR remanescentes em respostas 4xx (`"Não autenticado"`, `"Nome deve ter pelo menos 2 caracteres"`) ainda existem nos handlers — não estão na superfície de erro genérica do wrapper, mas vale endereçar no L07-01.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.1).
- `2026-04-17` — **Fix shipped**: wrapper endurecido (canonical envelope + Sentry span tags + always-on request_id), 37 rotas financeiras/platform wrappeadas, 11 testes novos do wrapper, CI guard criado, runbook publicado.
