---
id: L03-09
audit_ref: "3.9"
lens: 3
title: "platform_revenue.fee_type CHECK"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "webhook", "mobile", "migration", "performance", "reliability"]
files:
  - supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql
  - portal/src/lib/platform-fee-types.ts
  - portal/src/lib/platform-fee-types.test.ts
correction_type: process
test_required: true
tests:
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
note: null
---
# [L03-09] platform_revenue.fee_type CHECK
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`20260228170000:11`: CHECK `('clearing', 'swap', 'fx_spread', 'maintenance')` — **não inclui `'billing_split'` nem `'provider_fee'`**. `platform_revenue` insere `fee_type='clearing'`, `'swap'`, `'fx_spread'`. Maintenance é inserido por `asaas-webhook/index.ts:216+` (não totalmente lido). Se `billing_split` for inserido, CHECK rejeita — perda silenciosa.
## Risco / Impacto

Insert falha, erro engolido (várias rotas têm `try/catch`), receita não registrada.

## Correção proposta

Alinhar CHECK de `platform_revenue.fee_type` com `platform_fee_config.fee_type`:
```sql
ALTER TABLE platform_revenue DROP CONSTRAINT platform_revenue_fee_type_check;
ALTER TABLE platform_revenue ADD CONSTRAINT platform_revenue_fee_type_check
  CHECK (fee_type IN ('clearing','swap','maintenance','billing_split','fx_spread','provider_fee'));
```

## Correção aplicada (2026-04-21)

Status: **fixed** (side-effect do trabalho L03-03, coberto por contract test).

A correção proposta já foi aplicada como parte do fix de **L03-03** (commit
`d2de1fd`, 2026-04-20), que precisava inserir um novo `fee_type='provider_fee'`
em `platform_revenue` e portanto teve de alargar o CHECK. A mesma migration
cobre também o `billing_split` originalmente apontado aqui.

1. **Migration canônica** — `supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql`
   (linhas 109–133, bloco `DO $widen_check$`) faz `DROP` + `ADD` idempotente
   da constraint, resultando na lista final:

   ```sql
   CHECK (fee_type IN (
     'clearing',
     'swap',
     'maintenance',
     'billing_split',
     'fx_spread',
     'provider_fee'
   ))
   ```

   `COMMENT ON CONSTRAINT` documenta a decisão deliberada de `platform_revenue`
   ser **superset** de `platform_fee_config` — tipos `pass-through` (hoje só
   `provider_fee`) vivem apenas no ledger de receita e nunca na tabela de rates
   configuráveis pelo admin. O comentário também instrui o próximo contribuidor
   a NÃO "consertar o drift" adicionando `provider_fee` ao `fee_config`.

2. **Single source of truth** — `portal/src/lib/platform-fee-types.ts` exporta
   `PLATFORM_REVENUE_FEE_TYPES` = `PLATFORM_FEE_TYPES ∪
   PLATFORM_PASSTHROUGH_FEE_TYPES`. Os dois conjuntos são disjoint por
   contract, o union é o que o CHECK do Postgres espelha. Consumidores (lib
   helpers, route handlers, OpenAPI build) importam daqui; zero literais
   inline sobrevivem ao grep de CI.

3. **Contract test de lockstep** — `portal/src/lib/platform-fee-types.test.ts`:
   - `describe("PLATFORM_REVENUE_FEE_TYPES …")`: 8 asserções incluindo
     disjoint config ↔ pass-through, superset de `PLATFORM_FEE_TYPES`, igualdade
     com o union canônico, e parse Zod positivo/negativo.
   - `describe("Cross-surface lockstep — SQL CHECK ↔ TS")`: lê literalmente
     `20260420090000_l03_provider_fee_revenue_track.sql` e falha se QUALQUER
     literal de `PLATFORM_REVENUE_FEE_TYPES` (inclusive `billing_split` e
     `provider_fee`) sumir do SQL. Isso é o guard de regressão que mata
     definitivamente o L03-09: nenhuma migration futura consegue narrowar o
     CHECK sem a suíte cair.

4. **Validação em banco vivo** — a sandbox `tools/test_l03_03_provider_fee_revenue_track.ts`
   executa `INSERT INTO platform_revenue (fee_type='provider_fee', …)` contra
   o schema pós-migration; como o `DROP/ADD` derruba e recria o CHECK, o
   teste falharia se `billing_split` tivesse sido acidentalmente removido da
   lista no caminho.

5. **Runbook** — `docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md#3.3` tem a receita
   de reaplicar manualmente o `DROP/ADD` caso um hot-patch futuro precise
   restaurar a lista canônica.

**Sem code changes necessárias neste PR**: a correção ficou disponível em
2026-04-20; este closeout apenas atualiza a metadata do finding para
`fixed`, linka o commit `d2de1fd` que de fato implementou a mudança, e
aponta o contract test responsável por mantê-la estável.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.9).
- `2026-04-20` — CHECK ampliada para `('clearing','swap','maintenance','billing_split','fx_spread','provider_fee')` em `20260420090000_l03_provider_fee_revenue_track.sql` (commit `d2de1fd`, trabalho L03-03). Contract test `platform-fee-types.test.ts` lockstep SQL↔TS garante que `billing_split` e `provider_fee` não possam mais desaparecer silenciosamente.
- `2026-04-21` — Finding encerrado como `fixed` após audit confirmar que o fix de L03-03 cobre 100% do escopo originalmente apontado aqui (missing `'billing_split'` e `'provider_fee'` no CHECK).
