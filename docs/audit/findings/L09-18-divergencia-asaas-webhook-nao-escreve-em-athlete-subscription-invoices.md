---
id: L09-18
audit_ref: "9.18"
lens: 9
title: "Divergência: Asaas webhook não escreve em athlete_subscription_invoices (modelo canônico)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-24
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["finance", "billing", "webhook", "asaas", "subscriptions", "divergence", "ADR-0010"]
files:
  - supabase/functions/asaas-webhook/index.ts
  - supabase/migrations/20260424180000_l09_18_subscription_bridge.sql
  - supabase/migrations/20260421670000_l23_09_athlete_subscriptions.sql
  - supabase/migrations/20260304200000_financial_engine.sql
correction_type: code
test_required: true
tests:
  - tools/audit/check-billing-models-converged.ts
linked_issues: []
linked_prs: ["425fccf"]
owner: platform-finance
runbook: docs/runbooks/ASAAS_WEBHOOK_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Este finding rastreia a Fase 1 (F-CON-1) do plano definido em
  ADR-0010 (consolidação dos modelos de subscription). Ver
  docs/adr/ADR-0010-billing-subscriptions-consolidation.md para
  contexto completo das 3 fases e do raciocínio.
---
# [L09-18] Divergência: Asaas webhook não escreve em `athlete_subscription_invoices` (modelo canônico)

> **Lente:** 9 — CRO/Finance · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** fix-pending

**Camada:** Edge Function (Deno) + DB
**Personas impactadas:** atleta (paga, mas vê alerta vermelho de
"vencida" no dashboard porque a invoice nova nunca foi marcada
`paid`), coach/admin_master (vê discrepância: dashboard antigo diz
"Ativo", agenda nova diz "Vencido"), plataforma (MRR reportado
diverge entre os dois modelos; auditoria contábil falha em fechar)

## Achado

O backend opera **dois modelos paralelos de subscription**:

1. **Legado** — `coaching_subscriptions` (migration `20260304200000`).
   Status agregado por subscription (`active|late|paused|cancelled`),
   sem tabela de invoices.
2. **Novo / canônico** — `athlete_subscriptions` +
   `athlete_subscription_invoices` (migration `20260421670000`,
   finding L23-09). Status invoice-level
   (`pending|paid|overdue|cancelled`), 1 linha por mês, gerada por
   cron L09-13, marcada vencida por cron L09-14.

**O Asaas webhook (`supabase/functions/asaas-webhook/index.ts`)
escreve apenas no modelo legado.** Quando recebe `PAYMENT_CONFIRMED`
ele atualiza `coaching_subscriptions.status='active'` e
`last_payment_at=now()` — mas **NÃO** chama
`fn_subscription_mark_invoice_paid` (`SECURITY DEFINER`,
service-role) para fechar a invoice nova correspondente.

**Consequência observável em produção** (ou na primeira que rodar
após o cron L09-13 começar a gerar invoices):

| t | Evento | `coaching_subscriptions.status` | `athlete_subscription_invoices.status` (period_month corrente) |
|---|--------|---------------------------------|----------------------------------------------------------------|
| 0 | Cron L09-13 gera invoice do mês | `active` | `pending` |
| +1d | Atleta paga via Asaas | `active` (webhook atualiza) | `pending` (webhook ignora) |
| +6d | Cron L09-14 sweep | `active` | **`overdue` (FALSO POSITIVO)** |
| +6d | `FinancialAlertBanner` (L09-17) lê invoice | — | dispara **alerta VERMELHO** "vencida há 1 dia" para atleta que JÁ pagou |
| +6d | Coach abre `/financial/agenda` (L09-15) | — | mostra atleta como **inadimplente** |
| +6d | Coach abre `/financial/subscriptions` (legado) | "Ativo" | — |

Ou seja: **o atleta paga, recebe alerta vermelho, e o coach vê dois
dashboards contraditórios da mesma realidade**. O `FinancialAlertBanner`
acabou de ser shipado (L09-17, commit `252d227`) e essa divergência
o transforma em um disparador automático de churn por desconfiança
("paguei e tô vendo alerta vermelho?").

## Por que isso é critical agora

Antes de L09-13 (cron de geração) + L09-15 (agenda) + L09-16 (tela
do atleta) + L09-17 (banner) entrarem, `athlete_subscription_invoices`
existia mas era invisível em produto. A divergência era latente.

Com a Wave F slice 1-4 fechadas (todas em 2026-04-24), o modelo novo
agora é o que o atleta vê todo dia ao abrir o app, e o que o coach
vê na agenda. **A divergência é hoje user-facing**, e a UX é
estritamente pior do que se nenhum modelo novo existisse — dois
modelos contraditórios geram menos confiança que um modelo
incompleto.

## Correção proposta

Implementar a **Fase 1 (F-CON-1)** do
[ADR-0010](../../adr/ADR-0010-billing-subscriptions-consolidation.md)
— **bridge no webhook**, sem big-bang migration. Resumo:

### 1. Webhook Asaas chama `fn_subscription_mark_invoice_paid` no caminho de pagamento

Em `supabase/functions/asaas-webhook/index.ts`, no bloco que mapeia
`PAYMENT_CONFIRMED|PAYMENT_RECEIVED → 'active'` e atualiza
`coaching_subscriptions`, adicionar caminho paralelo:

- Resolver `(group_id, athlete_user_id)` a partir do legado (já
  resolvido para o update atual).
- Derivar `period_month` a partir do `payment.dueDate` do payload
  Asaas (primeiro dia do mês de vencimento).
- Tentar resolver a invoice nova:
  - Por `external_charge_id` se existir (preferido — exato).
  - Senão por `(athlete_user_id, group_id, period_month)`
    (fallback — boa-fé).
- Se encontrar invoice `pending|overdue`, chamar
  `fn_subscription_mark_invoice_paid` (`SECURITY DEFINER`,
  idempotente em `paid`).
- Se NÃO encontrar (subscription nova ainda não foi criada para esse
  atleta — caso comum durante a transição), **logar e continuar**.
  Fail-open: não bloqueia o webhook, não gera 5xx para o Asaas.

### 2. Migration que cria CI guard de convergência

Função PostgreSQL `fn_assert_subscription_models_converged` que:

- Para cada `coaching_subscriptions` com `status='active'` e
  `last_payment_at` no mês corrente,
- Verifica que existe `athlete_subscription_invoices` correspondente
  com `status='paid'` no mesmo `period_month` (quando há
  `athlete_subscriptions` para o par).
- Retorna até N samples de divergência. Wrapper `_assert` raise
  `P0010` se houver.
- Tolera o caso de "subscription nova ainda não criada" (durante
  Fase 1 esse é estado esperado), reportando-o como `info` separado
  do `error`.

### 3. CI / cron

- `npm run audit:billing-models-converged` (chama o detector,
  fail-loud em divergência > 0).
- Cron diário usando o scaffolding de `cron-health-monitor` (L06-04)
  que persiste samples em `cron_health_alerts` quando divergência
  aparecer.

### 4. Runbook tocado

- `docs/runbooks/ASAAS_WEBHOOK_RUNBOOK.md` ganha seção
  "Bridge para `athlete_subscription_invoices` (ADR-0010 F-CON-1)"
  documentando: (a) que o webhook agora escreve em 2 modelos, (b)
  como diagnosticar divergência via SQL, (c) como manualmente
  reconciliar uma invoice atrasada.

### 5. Idempotência e fail-open

- `fn_subscription_mark_invoice_paid` já é idempotente (no-op se
  invoice já está `paid`). Webhook pode ser reentregue 2x sem efeito
  duplicado.
- Erros do caminho novo são logados em `payment_webhook_events`
  (campo `processing_notes` ou similar) mas NÃO falham o evento.
  Fail-open porque a verdade contábil está sendo construída em
  paralelo: a única coisa pior do que divergência é perda de evento
  (que dispararia retry exponencial do Asaas e duplicação).

## Critérios de pronto

- [ ] Webhook Asaas chama `fn_subscription_mark_invoice_paid` em
      `PAYMENT_CONFIRMED|PAYMENT_RECEIVED` quando subscription nova
      existe.
- [ ] Webhook continua atualizando `coaching_subscriptions` (compat).
- [ ] Função `fn_assert_subscription_models_converged` existe + raise
      `P0010` em divergência.
- [ ] CI guard `audit:billing-models-converged` registrado em
      `package.json`.
- [ ] Integration test: simula `PAYMENT_CONFIRMED` para subscription
      que existe nos dois modelos → ambos ficam `paid|active`.
- [ ] Integration test: simula `PAYMENT_CONFIRMED` para subscription
      que existe SÓ no legado → legado vira `active`, log emitido,
      webhook responde 200.
- [ ] Integration test: idempotência (2× mesmo evento → 1× crédito).
- [ ] `ASAAS_WEBHOOK_RUNBOOK.md` atualizado.
- [ ] `audit:build` + `audit:verify` verdes.

## Referência narrativa

Decisão arquitetural completa (com Options A/B/C avaliadas e plano
F-CON-1/2/3 das 3 fases) em
[`docs/adr/ADR-0010-billing-subscriptions-consolidation.md`](../../adr/ADR-0010-billing-subscriptions-consolidation.md).

## Histórico

- `2026-04-24` — Identificado durante o trabalho de consolidação
  (ADR-0010). É o primeiro item executável das 3 fases acordadas
  (F-CON-1). Severidade `critical` porque com L09-17 já em produção
  o falso-positivo de alerta vermelho dispara churn por
  desconfiança.
- `2026-04-24` — **Fixed** (commit `425fccf`). Migration
  `20260424180000_l09_18_subscription_bridge.sql` ship 3 funções
  (`fn_subscription_bridge_mark_paid_from_legacy`,
  `fn_find_subscription_models_divergence`,
  `fn_assert_subscription_models_converged`) com pattern fail-soft
  WHEN OTHERS / fail-loud insufficient_privilege. Webhook
  `asaas-webhook/index.ts` chama o bridge em
  `PAYMENT_CONFIRMED|PAYMENT_RECEIVED` (fail-open). CI guard
  `audit:billing-models-converged` (43 invariantes estáticas) +
  `npm run audit:billing-models-converged`. Runbook
  `ASAAS_WEBHOOK_RUNBOOK.md §9` documenta diagnóstico, 7 reasons,
  recipe de reconciliação manual. Validado E2E com setup sintético
  (group + atleta + legacy_sub + new_sub + pending invoice):
  detector encontrou 1, bridge marcou paid (was_paid_now=true),
  invoice ficou status=paid + paid_at preenchido, detector voltou a
  0, segundo call retornou already_paid (idempotência ok).
