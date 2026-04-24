# ADR-0010 — Consolidação de Modelos de Subscription (legado `coaching_subscriptions` vs novo `athlete_subscriptions`)

- **Status:** Accepted
- **Date:** 2026-04-24
- **Deciders:** platform-finance (CRO/CFO), platform-backend
- **Context tag:** `L09`
- **Related finding(s):** [L09-18](../audit/findings/L09-18-divergencia-asaas-webhook-nao-escreve-em-athlete-subscription-invoices.md), [L23-09](../audit/findings/L23-09-billing-integrado-cobranca-de-mensalidade-aos-atletas.md), [L09-13](../audit/findings/L09-13-cron-fn-subscription-generate-cycle-ausente.md), [L09-14](../audit/findings/L09-14-cron-fn-subscription-mark-overdue-ausente.md), [L09-15](../audit/findings/L09-15-agenda-de-recebiveis-ausente.md), [L09-16](../audit/findings/L09-16-atleta-sem-tela-minhas-mensalidades.md), [L09-17](../audit/findings/L09-17-atleta-sem-alerta-mensalidade-vencendo.md)

## Context

O backend de `omni_runner` carrega **dois modelos paralelos** de subscription
de atleta — fruto de evolução incremental sem retrofit:

### Modelo legado — `coaching_subscriptions` (migration `20260304200000_financial_engine.sql`)

- 1 linha por `(group_id, athlete_user_id)` com `UNIQUE` total.
- `plan_id` aponta para `coaching_plans` (preço sai do plano).
- Status agregado: `active | late | paused | cancelled`.
- Apenas denormaliza `next_due_date` e `last_payment_at` — **não há tabela
  de invoices históricas**.
- É o **único** modelo escrito pelo `supabase/functions/asaas-webhook`
  (6 call-sites em `index.ts`) e lido por todo o portal financeiro
  exceto a página `/financial/agenda`:
  - `portal/.../financial/page.tsx` (KPIs)
  - `portal/.../financial/subscriptions/page.tsx` (listagem)
  - `portal/.../financial/subscriptions/assign/page.tsx` (criação)
  - `portal/.../financial/plans/page.tsx`
  - `portal/.../api/financial/subscriptions/route.ts`
  - `portal/.../api/financial/plans/route.ts`
  - `supabase/functions/billing-reconcile/index.ts`
- Status `late` é aplicado a partir de payload Asaas, sem distinção entre
  invoices vencidas (semanticamente errado: a subscription pode ter 3
  invoices `pending`, 1 `paid` e 1 `overdue` ao mesmo tempo).

### Modelo novo — `athlete_subscriptions` + `athlete_subscription_invoices` (migration `20260421670000_l23_09_athlete_subscriptions.sql`, finding [L23-09](../audit/findings/L23-09-billing-integrado-cobranca-de-mensalidade-aos-atletas.md))

- 1 linha em `athlete_subscriptions` por `(group_id, athlete_user_id)` ATIVA
  (UNIQUE parcial `WHERE status IN ('active','paused')`).
- `price_cents` e `currency` direto na subscription (sem FK para plano —
  permite negociação individual sem inflar o catálogo de planos).
- `gateway TEXT IN ('asaas','stripe','mercadopago')` — multi-gateway por design.
- Status agregado mais simples: `active | paused | cancelled` (sem `late`).
- **`athlete_subscription_invoices`** é a tabela canônica do estado de
  pagamento, 1 linha por `(subscription_id, period_month)` com UNIQUE,
  status `pending | paid | overdue | cancelled`, `due_date`, `paid_at`,
  `external_charge_id`, `external_invoice_url`.
- 6 RPCs `SECURITY DEFINER`:
  `fn_subscription_start / _pause / _cancel / _generate_cycle /
  _mark_invoice_paid / _mark_overdue`.
- Cron `pg_cron` (L09-13/L09-14) gera invoices mensalmente e marca
  vencidas — finalmente fechando o loop de receita previsível.
- Lido pelo Flutter (`AthleteMyInvoicesScreen`, `FinancialAlertBanner`)
  e pela página coach `/financial/agenda` (L09-15).

### Por que o paralelo é tóxico

1. **Divergência de verdade.** O webhook do Asaas marca
   `coaching_subscriptions.status='active'` quando recebe
   `PAYMENT_CONFIRMED`, mas **nunca** chama
   `fn_subscription_mark_invoice_paid` → a invoice nova fica `pending`,
   o cron `fn_subscription_mark_overdue` a vira `overdue`, o
   `FinancialAlertBanner` (L09-17) dispara alerta vermelho para um
   atleta que JÁ pagou. O dashboard antigo do coach mostra "Ativo", o
   app do atleta mostra "Vencida". Esse é o gap rastreado em
   [L09-18](../audit/findings/L09-18-divergencia-asaas-webhook-nao-escreve-em-athlete-subscription-invoices.md).
2. **Dois pontos de criação.** `assign/page.tsx` cria
   `coaching_subscriptions` (com `plan_id`); `fn_subscription_start`
   cria `athlete_subscriptions` (com `price_cents`). Atletas onboarded
   por caminhos diferentes ficam em modelos diferentes — auditoria
   contábil não bate.
3. **Status semântico incompatível.** `late` (subscription-level) não
   tem equivalente exato em `overdue` (invoice-level). Migrar mecânico
   é impossível sem regra de produto explícita ("subscription é `late`
   se ANY invoice é `overdue`?").
4. **Nenhum dos dois sozinho cobre o produto.** O legado tem o
   webhook + lugares já em UI. O novo tem invoice-level state, cron,
   multi-gateway e UI nova (atleta + agenda). Matar qualquer um sem
   migration de bridge quebra produção.

## Options considered

### Option A — Manter os dois modelos coexistindo (status quo)

- **Pros:** zero esforço imediato; não quebra nada hoje.
- **Cons:** divergência só piora à medida que features novas (push de
  vencimento L09-18-na-roadmap, aging report F3, agenda) escolhem um
  modelo "à mão"; auditoria fiscal ([L09-04](../audit/findings/L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md))
  vai exigir uma única fonte; KYC/AML ([L09-02](../audit/findings/L09-02-ausencia-de-kyc-aml-para-grupos-com-custodia.md))
  vai precisar `subscription_id` único. Decisão é apenas adiada com
  juros compostos.

### Option B — Big-bang migration: drop `coaching_subscriptions`, migrar tudo para `athlete_subscriptions` em uma PR

- **Pros:** elimina o paralelo de uma vez.
- **Cons:** 6 call-sites no portal + 6 no webhook + 1 no
  billing-reconcile + dependências em runbooks (DISPUTE_CHARGEBACK,
  ASAAS_WEBHOOK), em testes de integração, em
  `fn_delete_user_data_lgpd_complete`. Risco de quebrar webhook em
  produção (perda silenciosa de eventos `PAYMENT_CONFIRMED`) é
  inaceitável. Sem ambiente de staging financeiro
  ([L09 follow-up pending](../audit/ROADMAP.md)) o blast-radius é
  catastrófico.

### Option C — Faseado bridge → migração → drop (escolhido)

- Fase 1 — **bridge no webhook**: o webhook continua escrevendo em
  `coaching_subscriptions` MAS tambem chama
  `fn_subscription_mark_invoice_paid` quando consegue resolver
  `(group_id, athlete_user_id, period_month)`. Os dois modelos passam
  a convergir. Zero breaking change.
- Fase 2 — **leituras migradas + backfill**: o portal passa a ler de
  `athlete_subscriptions`/`_invoices`. Onboarding novo (`assign`) cria
  no novo. Migração one-shot copia subs ativas legadas → novo modelo
  (com `price_cents` derivado de `coaching_plans.price`).
- Fase 3 — **drop legado**: depois de 2 ciclos rodando em paralelo
  com convergência verificada (CI guard), `coaching_subscriptions`
  vira VIEW sobre o novo modelo (compat) e eventualmente é
  fisicamente droppada.
- **Pros:** cada fase é independente, idempotente, reversível,
  auditável. Bridge sozinha já fecha o gap urgente do L09-18.
- **Cons:** trabalho distribuído em 3 PRs; precisa CI guard que
  verifique convergência (sem ele, o bridge poderia silenciosamente
  divergir). Plano explícito de retirada do legado tem que ser
  registrado (este ADR).

## Decision

Adotamos **Option C — faseado**. O modelo canônico de longo prazo é
**`athlete_subscriptions` + `athlete_subscription_invoices`** porque:

1. Modela invoice-level (necessário para auditoria contábil e
   nota-fiscal).
2. Multi-gateway por design (necessário para Stripe/MercadoPago além
   de Asaas).
3. Já é o que o cron, a agenda do coach, e a UI do atleta enxergam.
4. Tem state-machine rigoroso com CHECK constraints.
5. Tem RPCs `SECURITY DEFINER` testadas e CI guard
   (`audit:athlete-subscriptions`, 56 invariantes).

**`coaching_subscriptions` é declarado deprecated** — não recebe
features novas a partir desta data. Será removido fisicamente após
Fase 3 (estimativa: 2 ciclos de billing após o bridge entrar em
produção, ou seja, ~60 dias depois de [L09-18](../audit/findings/L09-18-divergencia-asaas-webhook-nao-escreve-em-athlete-subscription-invoices.md)
shipar).

### Plano de fases (canônico)

| Fase | Trigger de saída | Findings | Status |
|------|------------------|----------|--------|
| **F-CON-1 — Bridge no webhook** | Asaas webhook chama `fn_subscription_mark_invoice_paid` quando subscription nova existe; CI guard verifica convergência (`coaching_subscriptions.status='active'` ⇔ ANY `athlete_subscription_invoices.status='paid'` no period_month corrente). | [L09-18](../audit/findings/L09-18-divergencia-asaas-webhook-nao-escreve-em-athlete-subscription-invoices.md) | 📋 fix-pending |
| **F-CON-2 — Migrar leituras + backfill** | Portal lê de `athlete_subscriptions`. Migration one-shot popula novo modelo a partir de `coaching_subscriptions` ativas, derivando `price_cents` de `coaching_plans.price`. `assign/page.tsx` passa a chamar `fn_subscription_start`. | TBD (L09-19?) | ⏳ planned |
| **F-CON-3 — Drop legado** | `coaching_subscriptions` vira VIEW compat (read-only) sobre o novo modelo. Após 2 ciclos: `DROP TABLE`. Webhook escreve apenas no novo modelo. | TBD (L09-20?) | ⏳ planned |

### Regras durante a transição (curto prazo)

1. **Nenhum código novo** lê ou escreve em `coaching_subscriptions`
   sem comentário `-- L09/ADR-0010 legacy bridge: reason`.
2. **Toda feature financeira nova** escolhe `athlete_subscriptions`
   por padrão.
3. CI guard `audit:adr` verifica que este ADR é referenciado pelo
   menos por uma migration de bridge (Fase 1) e por um lint que
   barra novos `coaching_subscriptions.upsert` no portal (depois da
   Fase 2 entrar).
4. Asaas webhook ganha **dois caminhos**: o legado (preserva
   compat) E a chamada nova (`fn_subscription_mark_invoice_paid`).
   Erros no caminho novo são logados mas NÃO falham o webhook —
   fail-open, porque a verdade contábil está sendo construída e a
   única coisa pior do que divergência é perda de evento.

## Consequences

### Positive

- **Convergência sem big-bang**: produção não quebra; bridge faz
  os modelos se reconciliarem em até 1 ciclo de billing.
- **Roteiro registrado**: 6 meses no futuro, qualquer dev novo abre
  este ADR e entende por que tem dois modelos e como/quando o
  legado some.
- **Desbloqueia features financeiras**: alerta de vencimento
  ([L09-17](../audit/findings/L09-17-atleta-sem-alerta-mensalidade-vencendo.md))
  e push notification (planejado em L09-18-followups) param de
  disparar falsos positivos.
- **Auditoria fiscal viabilizada**: invoice-level state habilita
  emissão de nota fiscal por evento `paid` (cf.
  [L09-04](../audit/findings/L09-04-nota-fiscal-recibo-fiscal-nao-emitida-em-withdrawals.md)).
- **Multi-gateway viabilizado**: Stripe/MercadoPago para mensalidade
  passam a ter onde aterrissar.

### Negative

- **Período de coabitação ~60 dias** com 2 modelos e 1 bridge —
  carga cognitiva extra para devs financeiros e mais um lugar para
  CI checar invariantes.
- **Risco de bridge divergir silenciosamente** se CI guard não for
  forte. Mitigação: o guard de F-CON-1 é fail-loud (raise P0010
  com até 10 samples de divergência) e roda em cron diário (aproveitar
  scaffolding de `cron-health-monitor`).
- **Backfill de Fase 2 precisa decisão de produto** sobre subscriptions
  legadas com `plan_id` que não tem `price` claro (ex: planos antigos
  com preço calculado em runtime). Se houver casos, listar em
  L09-19 quando criado.
- **Runbooks tocados**: `ASAAS_WEBHOOK_RUNBOOK.md` e
  `DISPUTE_CHARGEBACK_RUNBOOK.md` ganham seções "Bridge para
  athlete_subscription_invoices" durante F-CON-1.

### Follow-ups

- **L09-18** (criado neste mesmo PR) — implementar Fase 1 (bridge no
  webhook + CI guard de convergência).
- **L09-19** (a criar quando F-CON-1 fechar) — implementar Fase 2
  (backfill + migração de leituras + redirecionar `assign`).
- **L09-20** (a criar quando F-CON-2 fechar) — implementar Fase 3
  (DROP TABLE, virar VIEW compat se necessário, atualizar runbooks).
- Revisitar este ADR após F-CON-3 e marcar `Status: Implemented`
  (ou `Superseded by ADR-XXXX` se as fases revelarem necessidade
  de revisão estrutural).

## Links

- Findings: [L09-18](../audit/findings/L09-18-divergencia-asaas-webhook-nao-escreve-em-athlete-subscription-invoices.md), [L23-09](../audit/findings/L23-09-billing-integrado-cobranca-de-mensalidade-aos-atletas.md), [L09-13](../audit/findings/L09-13-cron-fn-subscription-generate-cycle-ausente.md), [L09-14](../audit/findings/L09-14-cron-fn-subscription-mark-overdue-ausente.md), [L09-15](../audit/findings/L09-15-agenda-de-recebiveis-ausente.md), [L09-16](../audit/findings/L09-16-atleta-sem-tela-minhas-mensalidades.md), [L09-17](../audit/findings/L09-17-atleta-sem-alerta-mensalidade-vencendo.md)
- Migrations: `supabase/migrations/20260304200000_financial_engine.sql` (legado), `supabase/migrations/20260421670000_l23_09_athlete_subscriptions.sql` (novo), `supabase/migrations/20260424160000_l09_13_subscription_crons.sql` (cron), `supabase/migrations/20260424170000_l09_15_financial_agenda.sql` (agenda RPC)
- Runbooks: `docs/runbooks/ASAAS_WEBHOOK_RUNBOOK.md`, `docs/runbooks/DISPUTE_CHARGEBACK_RUNBOOK.md`
- Code (legado, a migrar): `portal/src/app/(portal)/financial/page.tsx:30`, `portal/src/app/(portal)/financial/subscriptions/page.tsx:28`, `portal/src/app/(portal)/financial/subscriptions/assign/page.tsx:43`, `portal/src/app/(portal)/financial/plans/page.tsx:36`, `portal/src/app/api/financial/subscriptions/route.ts:41`, `portal/src/app/api/financial/plans/route.ts:104`, `supabase/functions/asaas-webhook/index.ts:122`, `supabase/functions/billing-reconcile/index.ts:232`
- Code (novo, canônico): `portal/src/app/(portal)/financial/agenda/page.tsx`, `omni_runner/lib/data/services/athlete_subscription_invoice_service.dart`, `omni_runner/lib/presentation/screens/athlete_my_invoices_screen.dart`, `omni_runner/lib/presentation/widgets/financial_alert_banner.dart`
