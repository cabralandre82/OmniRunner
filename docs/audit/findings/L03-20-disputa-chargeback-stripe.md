---
id: L03-20
audit_ref: "3.20"
lens: 3
title: "Disputa / chargeback Stripe"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["lgpd", "finance", "atomicity", "webhook", "mobile", "edge-function"]
files:
  - portal/src/app/api/custody/webhook/route.ts
  - portal/src/lib/custody.ts
  - supabase/migrations/20260421150000_l03_13_hotfix_ambiguous_refs.sql
  - supabase/migrations/20260421160000_l03_dispute_chargeback_flow.sql
correction_type: process
test_required: true
tests:
  - portal/src/app/api/custody/webhook/route.test.ts  # 29/29 (12 novos dispute-path)
  - tools/test_l03_20_dispute_chargeback.ts           # 14/14 pgsandbox
  - supabase/migrations/20260421160000_l03_dispute_chargeback_flow.sql  # self-test in-migration (4 branches)
linked_issues: []
linked_prs:
  - 4b5aaed
  - 8acfde7
owner: platform-ops@omnirunner.app
runbook: docs/runbooks/DISPUTE_CHARGEBACK_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---

# [L03-20] Disputa / chargeback Stripe

> **Lente:** 3 — CFO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** BACKEND
**Personas impactadas:** Plataforma, Assessoria

## Achado original

`supabase/functions/asaas-webhook/index.ts` mapeia `PAYMENT_REFUNDED → cancelled` mas isso só altera `coaching_subscriptions.status`. **Não reverte custody_deposit nem retira coins já emitidas**. Para custody webhooks (`/api/custody/webhook` Stripe/MP), nenhum caminho trata `payment_intent.succeeded` vs `charge.dispute.created` — apenas confirma depósitos.

## Risco / Impacto

Chargeback 60-120 dias após depósito: dinheiro volta ao usuário, mas coins já foram distribuídas a atletas. Invariante `deposited >= committed` quebrada, plataforma absorve prejuízo e a operação só descobre semanas depois quando `check_custody_invariants()` alerta.

## Correção implementada (2026-04-21)

### 1. Migration `20260421160000_l03_dispute_chargeback_flow.sql`

**Seeds** `platform_webhook_system` em `auth.users` com uuid constante
`11111111-1111-1111-1111-111111111111` — ator sintético usado como
`p_actor_user_id` nas reversões disparadas por webhook. Exposto via
`public.platform_webhook_system_user_id()`.

**Cria tabela** `custody_dispute_cases` com estados
`OPEN / RESOLVED_REVERSED / ESCALATED_CFO / DEPOSIT_NOT_FOUND / DISMISSED`
e UNIQUE `(gateway, gateway_event_id)` como primitivo de idempotência.
RLS: `platform_admin` SELECT-all; staff do grupo SELECT dos próprios
casos. Índice parcial `state IN ('OPEN','ESCALATED_CFO')` para o painel
admin de fila.

**Cria função** `fn_handle_custody_dispute_atomic(...)` — orquestrador
atômico:

| entrada                                           | outcome             |
| ------------------------------------------------- | ------------------- |
| `(gateway, event_id)` já existe                   | `idempotent_replay` |
| `payment_reference` sem deposit                   | `deposit_not_found` |
| deposit.status ≠ `confirmed`                      | `dismissed`         |
| `reverse_custody_deposit_atomic` OK               | `reversed`          |
| `reverse_…` rejeita `INVARIANT_VIOLATION` (P0008) | `escalated`         |

Auto-test em migration-time com sentinel exception + rollback exercita
os 4 branches principais.

### 2. Route `POST /api/custody/webhook` — classificador

Novo helper `classifyEvent(event, gateway)` devolve
`{kind: success|dispute|refund|chargeback|unsupported, paymentReference, gatewayDisputeRef, reasonCode}`.
Mapeamentos:

| Stripe                                                          | kind          |
| --------------------------------------------------------------- | ------------- |
| `payment_intent.succeeded`, `checkout.session.completed`        | `success`     |
| `charge.dispute.created`, `charge.dispute.funds_withdrawn`      | `chargeback`  |
| `charge.dispute.closed` com `status=lost`                       | `chargeback`  |
| `charge.dispute.closed` com `status=won/warning_*`              | `unsupported` |
| `charge.refunded`, `refund.created`, `charge.refund.updated`    | `refund`      |
| qualquer outro                                                  | `unsupported` |

| MercadoPago                                                     | kind          |
| --------------------------------------------------------------- | ------------- |
| `action=payment.refunded` ou `data.status=refunded`             | `refund`      |
| `action=payment.charged_back` ou `data.status=charged_back`     | `chargeback`  |
| `action=payment.updated/created` ou `type=payment`              | `success`     |
| qualquer outro                                                  | `unsupported` |

Para Stripe o `paymentReference` em eventos de dispute/refund vem de
`data.object.payment_intent` (NÃO de `data.object.id`, que é o id do
próprio `du_…` / `re_…`). O helper trata.

### 3. Novo lib helper `handleCustodyDispute()`

Tipo-seguro, wrap do RPC `fn_handle_custody_dispute_atomic` em
`portal/src/lib/custody.ts`. Degrada gracefully (`return null`) quando
a RPC está ausente (installs legados).

### 4. Hotfix colateral `20260421150000_l03_13_hotfix_ambiguous_refs.sql`

Ao montar o sandbox para L03-20, descobrimos 3 bugs latentes nas funções
L03-13 (`reverse_coin_emission_atomic`, `reverse_burn_atomic`,
`reverse_custody_deposit_atomic`) — colunas ambíguas entre `RETURNS TABLE`
e tabelas físicas (ex. `new_balance`, `group_id`, `athlete_user_id`),
além de `clearing_settlements.status = 'cancelled'` que violaria a
CHECK original. A hotfix estende a CHECK constraint para admitir
`'cancelled'` e recria as 3 funções com aliases explícitos e
`#variable_conflict use_variable`. Sem essa hotfix, L03-20 não
conseguiria rodar `reverse_custody_deposit_atomic` em runtime.

### 5. Asaas webhook — sem mudança necessária

Asaas hoje dirige apenas `coaching_subscriptions` (cobrança de
assinaturas), não `custody_deposits`. Um `PAYMENT_REFUNDED` no Asaas
corretamente transiciona a subscription para `cancelled` — não há
lastro custodial para desfazer. Se no futuro Asaas vier a alimentar
`custody_deposits`, o mesmo wiring vale: a função
`fn_handle_custody_dispute_atomic` já aceita `gateway='asaas'`.
Documentado em `DISPUTE_CHARGEBACK_RUNBOOK.md §"escopo de gateways"`.

## Testes

- **vitest** `portal/src/app/api/custody/webhook/route.test.ts` —
  29/29 pass (17 pré-existentes + 12 novos):
  happy-path reverse, refund routing, escalate path (`INVARIANT_VIOLATION`),
  idempotent replay, `deposit_not_found`, `charge.dispute.closed:lost`
  vs `won`, MercadoPago `payment.refunded`, RPC indisponível (503),
  RPC throw (500), evento não-suportado (200 skip).

- **pg sandbox** `tools/test_l03_20_dispute_chargeback.ts` —
  14/14 pass contra DB local: registry + permissões, seed
  `platform_webhook_system`, happy-path end-to-end
  (deposit.status=refunded, account debited, coin_reversal_log
  escrito, portal_audit_log populado), idempotência preserva estado,
  escalation não toca account, deposit_not_found / dismissed /
  validation paths.

- **migration self-test** — bloco `DO $self_test$` no próprio
  `20260421160000_…_dispute_chargeback_flow.sql` exercita os 4
  branches e rolla-back via sentinel exception antes do COMMIT.

## Runbook operacional

[`docs/runbooks/DISPUTE_CHARGEBACK_RUNBOOK.md`](../../runbooks/DISPUTE_CHARGEBACK_RUNBOOK.md)
— triagem de `/platform/disputes`, interpretação dos estados,
escalação CFO, resolução manual via `CHARGEBACK_RUNBOOK §3.3`
(dívida-do-grupo), convenções de auditoria.

## Referência narrativa

Contexto completo e motivação detalhada em
[`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.20]`.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.20).
- `2026-04-21` — **Fixado**. Migration + webhook classifier + 43 testes
  (29 vitest + 14 pgsandbox). Hotfix colateral L03-13 aplicado.
