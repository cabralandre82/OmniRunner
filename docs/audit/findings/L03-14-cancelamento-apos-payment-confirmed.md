---
id: L03-14
audit_ref: "3.14"
lens: 3
title: "Cancelamento após PAYMENT_CONFIRMED"
severity: na
status: duplicate
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["finance", "subscription", "webhook"]
files:
  - "supabase/functions/asaas-webhook/index.ts"
  - "supabase/migrations/20260421160000_l03_dispute_chargeback_flow.sql"
  - "supabase/migrations/20260421130000_l03_reverse_coin_flows.sql"
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: L03-20
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: item umbrella CFO cobrido pelo fluxo L03-20 (chargeback) + L03-13 (reverse_burn) + webhook state map (asaas-webhook/index.ts:46-51)."
---
# [L03-14] Cancelamento após PAYMENT_CONFIRMED
> **Lente:** 3 — CFO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** 🔗 duplicate
**Camada:** BACKEND
**Personas impactadas:** Atleta, Assessoria, Plataforma

## Achado original
Preocupação: o que acontece quando uma subscription é cancelada **após** `PAYMENT_CONFIRMED`? Custody deposit reverte? Coins são retidas?

## Re-auditoria 2026-04-24

O ciclo de vida pós-pagamento é governado pelo webhook Asaas e tem tratamento idempotente para todos os estados:

### State map (`supabase/functions/asaas-webhook/index.ts:46-51`)
```ts
const STATUS_MAP: Record<string, string> = {
  PAYMENT_CONFIRMED: "active",
  PAYMENT_RECEIVED:  "active",
  PAYMENT_OVERDUE:   "grace",
  PAYMENT_REFUNDED:  "cancelled",
  PAYMENT_DELETED:   "paused",
};
```

### Cenários cobertos
| Cenário | Tratamento | Finding responsável |
|---|---|---|
| **Cancelamento voluntário pós-pagamento** (usuário cancela subscription, mas já pagou o mês) | Subscription → `cancelled`, mas custody_deposit e coins ficam (serviço foi prestado). Comportamento esperado — usuário pagou pelo período. | Normal lifecycle (não é bug) |
| **Chargeback (disputa)** | Webhook Stripe/MP/Asaas dispara `charge.dispute.created` → executa reversão de custody + retração de coins distribuídas | ✅ [L03-20](./L03-20-disputa-chargeback-stripe.md) (fixed) |
| **Refund (PAYMENT_REFUNDED)** | Webhook mapeia para `cancelled` e dispara `reverse_burn` / `refund_deposit` RPCs | ✅ [L03-13](./L03-13-reembolso-estorno-nao-ha-funcao-reverse-burn-ou-refund-deposit.md) (fixed) |
| **Pedido pendente eternamente** | Cron `expire-stale-deposits` após 48h | ✅ [L03-15](./L03-15-pedido-eternamente-pendente.md) (fixed) |

### Conclusão
Todas as transições relevantes para "cancelamento após PAYMENT_CONFIRMED" têm tratamento dedicado e funções de reversão (`reverse_burn`, `refund_deposit`, dispute handler, expire-stale-deposits cron). Este finding é um apontador umbrella que aponta para ação distribuída em L03-13, L03-15 e L03-20.

Marcado como `duplicate_of: L03-20` (mais abrangente para o caso pós-confirmação).

## Referência narrativa
Contexto completo em [`docs/audit/parts/02-cto-cfo.md`](../parts/02-cto-cfo.md) — anchor `[3.14]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.14).
- `2026-04-24` — Re-auditoria consolidou como duplicate de L03-20 (todos os caminhos já tratados).
