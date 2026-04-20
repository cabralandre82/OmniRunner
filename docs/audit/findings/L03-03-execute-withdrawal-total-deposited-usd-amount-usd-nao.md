---
id: L03-03
audit_ref: "3.3"
lens: 3
title: "execute_withdrawal — total_deposited_usd -= amount_usd não contabiliza fee do provider"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-20
tags: ["finance", "portal", "migration", "reliability"]
files:
  - portal/src/lib/platform-fee-types.ts
  - portal/src/lib/platform-fee-types.test.ts
  - supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql
  - tools/test_l03_03_provider_fee_revenue_track.ts
  - docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md
correction_type: process
test_required: true
tests:
  - tools/test_l03_03_provider_fee_revenue_track.ts
  - portal/src/lib/platform-fee-types.test.ts
linked_issues: []
linked_prs:
  - d2de1fd
owner: cfo
runbook: WITHDRAW_STUCK_RUNBOOK#3.3
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  ## Problema

  `createWithdrawal` (`portal/src/lib/custody.ts:368-414`) computa
  `localAmount = convertFromUsdWithSpread(amount_usd - provider_fee_usd, fx_rate, spread_pct)` —
  o usuário recebe local pelo NET (gross menos a taxa do gateway).

  `execute_withdrawal` (migration original `20260228170000:131-134`)
  porém faz `total_deposited_usd -= v_amount` (GROSS) e só registra
  `fx_spread` em `platform_revenue`. O `provider_fee_usd` simplesmente
  desaparecia da custódia sem lançamento contábil. Em um saque de
  $1000 com $100 provider_fee + $30 fx_spread:

  - custódia perde **$1000** (gross) ✓
  - usuário recebe **$870** em moeda local
  - `platform_revenue.fx_spread` recebe **$30**
  - `platform_revenue.provider_fee` recebe **$0** ← bug

  Resultado: $100 some do balance contábil em todo saque com gateway
  fee. Invariante `deposits_in = withdrawals_out + revenue + held`
  furada por exatamente o `provider_fee` por saque.

  ## Solução (5 camadas)

  1. **Schema** — migration
     `supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql`
     amplia o CHECK de `platform_revenue.fee_type` para incluir
     `'provider_fee'`. **Não** amplia `platform_fee_config.fee_type` —
     divergência deliberada porque provider_fee é pass-through (gateway
     fica com o dinheiro), não é configurável via UI.

  2. **`execute_withdrawal`** — re-criada com bloco simétrico ao
     `fx_spread`: se `provider_fee_usd > 0`, insere uma linha
     `'provider_fee'` em `platform_revenue` com
     `description='Gateway/provider fee on withdrawal (pass-through)'`.

  3. **`fail_withdrawal`** (L02-06) — re-criada para deletar AMBAS as
     linhas de `platform_revenue` (`fx_spread` + `provider_fee`) na
     mesma TX do refund de `total_deposited_usd`. O `audit_log`
     ganha campos novos: `fx_spread_reversed_usd` e
     `provider_fee_reversed_usd` separados, além do total agregado em
     `revenue_reversed_usd` (mantendo o contrato de retorno do L02-06).
     Bonus: corrige bug latente de coluna `status` ambígua que o L02-06
     introduziu (column reference colide com OUT param do RETURNS
     TABLE) — o teste de integração regredia o problema.

  4. **`_enqueue_fiscal_receipt`** (L09-04 trigger) — re-criada para
     curto-circuitar em `fee_type='provider_fee'`. Lei tributária
     brasileira: pass-through não é receita de serviço da plataforma,
     então não deve gerar NFS-e. Sem o curto-circuito o trigger
     dispararia, bateria no CHECK de `fiscal_receipts.fee_type` e
     emitiria `RAISE WARNING [L09-04]` ruidoso por linha.

  5. **Single source of truth TS** — `portal/src/lib/platform-fee-types.ts`
     ganha `PLATFORM_REVENUE_FEE_TYPES` (superset = `PLATFORM_FEE_TYPES`
     ∪ `PLATFORM_PASSTHROUGH_FEE_TYPES`) e
     `platformRevenueFeeTypeSchema`. Os contract-locks em
     `platform-fee-types.test.ts` são estendidos para 23 testes (de 9)
     cobrindo a divergência configurable-vs-passthrough nas 5
     superfícies (TS const, Zod, OpenAPI, SQL CHECK platform_revenue,
     SQL CHECK platform_fee_config + L09-04 trigger short-circuit).

  ## Verificação

  ### Self-test in-TX da migration
  ```
  NOTICE:  [L03-03.self_test] platform_revenue accepts provider_fee;
  platform_fee_config still rejects it; fiscal_receipts trigger
  short-circuits on provider_fee (deliberate divergence verified)
  ```

  ### Integração end-to-end (`tools/test_l03_03_provider_fee_revenue_track.ts`)
  ```
  ✓ provider_fee=0 + fx_spread=0: no revenue rows, custody debited gross
  ✓ provider_fee=0 + fx_spread>0: only fx_spread row, custody debited gross
  ✓ provider_fee>0 + fx_spread=0: only provider_fee row, custody debited gross
  ✓ provider_fee>0 + fx_spread>0: BOTH rows present, distinct types
  ✓ reverses fx_spread + provider_fee + refunds custody + audit breakdown
  ✓ idempotent on second call against already-failed row
  ✓ platform_revenue accepts fee_type='provider_fee'
  ✓ platform_fee_config rejects fee_type='provider_fee' (deliberate divergence)
  ✓ _enqueue_fiscal_receipt trigger short-circuits on provider_fee
  9 passed, 0 failed
  ```

  ### Contract-lock TS (`platform-fee-types.test.ts`)
  ```
  Test Files  1 passed (1)
       Tests  23 passed (23)
  ```

  ### Vitest full suite + lint + audit verify
  - `npx vitest run` → **1318 passed | 4 todo (1322)** (+14 vs. baseline 1304)
  - `npm run lint`   → **No ESLint warnings or errors**
  - `npx tsx tools/audit/verify.ts` → **348 findings validados**

  ## Backfill

  Withdraws **anteriores a 2026-04-20** com `provider_fee_usd > 0` e
  status `processing/completed` ainda têm o gap contábil (executaram
  contra a função antiga). A `WITHDRAW_STUCK_RUNBOOK §4.2` traz a
  query de auditoria para identificá-los e a query de reconciliação
  manual (insere a linha `provider_fee` retroativa com a data
  original, marcada `description='L03-03 backfill — ...'` para
  rastreabilidade). Backfill automatizado **não** está em escopo
  desta correção (pequeno volume; CFO faz batch único em janela de
  manutenção).

  ## Histórico relacionado
  - L01-44 / L01-45 — drift do `fee_type` em 5 superfícies. Esta
    correção estende o single-source-of-truth criado em L01-45 para
    cobrir a separação configurable-vs-passthrough.
  - L02-06 — `fail_withdrawal` original já fazia delete de
    `fx_spread`; agora também faz de `provider_fee` no mesmo TX.
---
# [L03-03] execute_withdrawal — total_deposited_usd -= amount_usd não contabiliza fee do provider
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-20)
**Camada:** BACKEND
**Personas impactadas:** Assessoria, Plataforma

## Achado
`createWithdrawal` (`portal/src/lib/custody.ts:324-370`) calcula `localAmount = convertFromUsdWithSpread(amountUsd - providerFee, fxRate, spreadPct)` — o `providerFeeUsd` reduz o USD antes de converter para local.
  - `execute_withdrawal` (migration 20260228170000:120-123) faz `total_deposited_usd -= v_amount` onde `v_amount = amount_usd = input gross`.

## Risco / Impacto

Buraco contábil: USD some da custódia mas não aparece nem como revenue nem como saque. Invariante contábil quebra no balanço total. CFO não consegue explicar.

## Correção aplicada

Ver bloco `note` no frontmatter para descrição completa em 5 camadas. Resumo:

1. Migration `20260420090000_l03_provider_fee_revenue_track.sql` amplia o CHECK de `platform_revenue.fee_type` para incluir `'provider_fee'` (mantém divergência deliberada com `platform_fee_config.fee_type` — passthrough não é configurável).
2. `execute_withdrawal` re-criada para inserir linha `provider_fee` quando `> 0`.
3. `fail_withdrawal` re-criada para reverter AMBAS as linhas (`fx_spread` + `provider_fee`) e quebra do bug latente de `status` ambíguo.
4. Trigger L09-04 `_enqueue_fiscal_receipt` curto-circuita em `provider_fee` (não gera NFS-e — pass-through).
5. `lib/platform-fee-types.ts` ganha `PLATFORM_REVENUE_FEE_TYPES` superset + 14 contract-locks novos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.3]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.3).
- `2026-04-20` — Corrigido. Migration + canonical TS + 9 testes integração + 14 contract-locks + runbook §3.3 atualizado + §4.2 backfill query.
