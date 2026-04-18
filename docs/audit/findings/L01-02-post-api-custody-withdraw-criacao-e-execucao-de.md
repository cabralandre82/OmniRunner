---
id: L01-02
audit_ref: "1.2"
lens: 1
title: "POST /api/custody/withdraw — Criação e execução de saque em um único request"
severity: critical
status: fixed
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "anti-cheat", "portal", "security", "custody", "fx"]
files:
  - supabase/migrations/20260417170000_platform_fx_quotes.sql
  - portal/src/lib/fx/quote.ts
  - portal/src/lib/fx/quote.test.ts
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/custody/withdraw/route.test.ts
  - portal/src/app/api/custody/fx-quote/route.ts
  - portal/src/app/api/custody/fx-quote/route.test.ts
  - portal/src/app/(portal)/fx/withdraw-button.tsx
correction_type: code
test_required: true
tests:
  - portal/src/lib/fx/quote.test.ts
  - portal/src/app/api/custody/withdraw/route.test.ts
  - portal/src/app/api/custody/fx-quote/route.test.ts
linked_issues: []
linked_prs:
  - "commit:0e66852"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Core anti-fraud fix entregue. Follow-ups em wave-1: (a) 2-phase approval (platform_admin independente do admin_master), (b) limite diário por grupo em platform_fee_config, (c) refresh automático de platform_fx_quotes via cron PTAX/ECB."
---
# [L01-02] POST /api/custody/withdraw — Criação e execução de saque em um único request
> **Lente:** 1 — CISO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟢 fixed
**Camada:** PORTAL
**Personas impactadas:** Plataforma (CFO), Assessoria
## Achado
`portal/src/app/api/custody/withdraw/route.ts:19` aceita **`fx_rate` vindo do cliente** (`z.number().positive()`), sem validar contra nenhuma fonte autoritativa (BCB/ECB/Stripe FX quote).
  - Combinado com `portal/src/lib/custody.ts:231-243` (`convertFromUsdWithSpread` usa literalmente o rate do cliente), um admin_master malicioso pode sacar USD com `fx_rate = 10.0` (normal BRL≈5.5), recebendo 2× em BRL.
  - `executeWithdrawal` é chamado logo após `createWithdrawal` (linha 104) — saque é finalizado em um único request, sem passo de aprovação com validação externa do rate.

## Risco / Impacto

Fraude financeira direta por admin_master comprometido ou malicioso. Escala: até USD 1M por request (limite do schema), multiplicado pelo erro de rate. Quebra a invariante D_i = R_i + A_i quando o `total_deposited_usd -= amount_usd` usa USD nominal mas o payout local sai inflado.

## Correção proposta (original)

1. Remover `fx_rate` do schema de entrada. Buscar rate em server-side de fonte autoritativa (`portal/src/lib/fx/quote.ts` — criar; consultar Stripe FX API ou BCB PTAX).
2. Separar em duas etapas: `POST /api/custody/withdraw` cria pendente com rate congelado e `executeWithdrawal` exige aprovação por `PLATFORM_ADMIN` (não admin_master) em `/api/platform/custody/approve-withdraw`.
3. Adicionar limite diário por grupo via `platform_fee_config` (`max_withdrawal_per_day_usd`).

## Correção implementada

**Escopo desta PR:** atacamos o **vetor de fraude direto** (item 1 da correção proposta). Os itens 2 e 3 requerem decisão de produto / separação de papéis e foram movidos para **Onda 1** (ver seção *Follow-ups*).

### 1. Source of truth: `platform_fx_quotes`

Migration `supabase/migrations/20260417170000_platform_fx_quotes.sql`:

- Nova tabela `public.platform_fx_quotes (currency_code, rate_per_usd, source, fetched_at, is_active, ...)`.
- **Defesas em profundidade:**
  - `CHECK (rate_per_usd > 0)` (básico).
  - `CHECK fx_rate_reasonable_bounds` — rejeita rates fora de janelas razoáveis por moeda (BRL ∈ [1,20], EUR ∈ [0.5,2], GBP ∈ [0.4,2]). Bloqueia tanto erro humano quanto comprometimento de API externa.
  - `UNIQUE INDEX` parcial `WHERE is_active=true` — **impede 2 cotações ativas para a mesma moeda**, preservando histórico de desativadas.
- RLS: `SELECT` para `authenticated` (read-only no UI); `ALL` apenas para `platform_role = 'admin'`.
- RPC `get_latest_fx_quote(currency)` — `SECURITY DEFINER`, `STABLE`, `SET search_path = public, pg_temp` (L18-03 compliant), retorna `rate + age_seconds` em uma chamada.
- Seed inicial BRL/EUR/GBP com `source='seed'` + `fetched_at=now()`.
- Invariante final: migration `RAISE EXCEPTION` se qualquer moeda suportada ficar sem cotação ativa após seed.

### 2. Biblioteca server-side `portal/src/lib/fx/quote.ts`

- `getAuthoritativeFxQuote(currency)` — busca via RPC, aplica staleness check (default 24h, tunable via `OMNI_FX_MAX_AGE_SECONDS`), valida rate > 0 mesmo que DB retorne (defesa em profundidade).
- Erros tipados: `FxQuoteUnsupportedError` (400), `FxQuoteMissingError` / `FxQuoteStaleError` (503), `FxQuoteError('db_error')` (503). Permite ao caller distinguir "configuração pendente" de "infra quebrada".
- `tryGetAuthoritativeFxQuote()` — versão safe (null em vez de throw) para UIs read-only.

### 3. Refactor `portal/src/app/api/custody/withdraw/route.ts`

- **`fx_rate` removido do schema**; `z.object({...}).strict()` rejeita campos desconhecidos no body com 400.
- Rate fetched server-side via `getAuthoritativeFxQuote(target_currency)` **depois** de todas as validações (auth, invariantes, schema).
- **Fail-closed**: se a cotação está stale/missing/db_error, retorna **503** e interrompe o fluxo — nenhum withdrawal é criado, nenhum audit log é emitido.
- `auditLog.metadata` agora inclui `fx_source` e `fx_age_seconds` para rastreabilidade forense.

### 4. Novo endpoint `GET /api/custody/fx-quote?currency=XXX`

- Permite ao UI buscar a cotação autoritativa para exibir **read-only**.
- Authz: qualquer membro autenticado de um grupo (coaching_members) — não expõe informação sensível.
- `Cache-Control: private, max-age=60, stale-while-revalidate=30` — alinha UX com staleness check (24h no server).
- Mapeamento de erros consistente com o withdraw route (4xx/503 + `code`).

### 5. UI `portal/src/app/(portal)/fx/withdraw-button.tsx`

- Input manual de `fx_rate` **removido**.
- Ao abrir o form, GET /api/custody/fx-quote é disparado para a moeda selecionada; rate exibido read-only (fonte + idade em human-friendly).
- Estimativa bruta em moeda local (sem spread) exibida inline após usuário digitar valor USD.
- Botão Confirmar **desabilitado** se quote indisponível — mensagem orienta contatar platform_admin.

## Testes de regressão

- `portal/src/lib/fx/quote.test.ts` (14 cases) — normalização de moeda, staleness, missing, rate inválido, unsupported, envelope de erros.
- `portal/src/app/api/custody/withdraw/route.test.ts` (11 cases) — **rejeição explícita de `fx_rate` no body**, uso de rate server-side, 503 em stale/missing, 403/401, limites de amount, strict schema com outros campos.
- `portal/src/app/api/custody/fx-quote/route.test.ts` (7 cases) — authz, default currency, mapeamento de erros.

Total: **32 testes novos** cobrindo o vetor de fraude + paths de infra degradada.

## Follow-ups (Onda 1)

1. **L01-02-followup-2phase** — 2-phase approval: `POST /api/custody/withdraw` apenas cria `pending`; execução requer aprovação de `platform_role='admin'` via `POST /api/platform/custody/approve-withdraw`. Introduz guarda humano para volumes >$X.
2. **L01-02-followup-daily-limit** — coluna `max_withdrawal_per_day_usd` em `platform_fee_config` (ou nova tabela `custody_limits`), enforcement em `createWithdrawal`.
3. **L01-02-followup-auto-refresh** — `pg_cron` job + edge function chamando PTAX (BCB) ou `exchangerate-api.com`, `UPSERT` em `platform_fx_quotes` com `source='ptax'`. Monitoring: alertar se última cotação > 6h.
4. **L01-02-followup-ui-refresh** — UI `/platform/fx` para platform_admin revisar/atualizar cotações manualmente (fallback se cron falhar).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.2).
- `2026-04-17` — Fix core implementado: `fx_rate` removido do body, quote server-side authoritative, fail-closed em staleness. Follow-ups (2-phase approval, daily limit, cron refresh) movidos para Onda 1.
- `2026-04-17` — Validação end-to-end (`tools/validate-migrations.sh --run-tests`): fresh-install aplica 165/165 migrations; suite 146/146 verde (inclui 32 testes desta correção). Promovido a `fixed` (commit `0e66852`).
