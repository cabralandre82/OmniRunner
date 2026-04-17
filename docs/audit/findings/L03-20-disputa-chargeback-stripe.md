---
id: L03-20
audit_ref: "3.20"
lens: 3
title: "Disputa / chargeback Stripe"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "finance", "atomicity", "webhook", "mobile", "edge-function"]
files:
  - supabase/functions/asaas-webhook/index.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L03-20] Disputa / chargeback Stripe
> **Lente:** 3 — CFO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Plataforma, Assessoria
## Achado
`supabase/functions/asaas-webhook/index.ts` mapeia `PAYMENT_REFUNDED → cancelled` mas isso só altera `coaching_subscriptions.status`. **Não reverte custody_deposit nem retira coins já emitidas**. Para custody webhooks (`/api/custody/webhook` Stripe/MP), nenhum caminho trata `payment_intent.succeeded` vs `charge.dispute.created` — apenas confirma depósitos.
## Risco / Impacto

Chargeback 60-120 dias após depósito: dinheiro volta ao usuário, mas coins já foram distribuídas a atletas. Invariante quebrada, plataforma absorve prejuízo.

## Correção proposta

Adicionar handler de `charge.dispute.created` e `charge.refunded` no webhook:
```typescript
if (event.type === "charge.dispute.created" || event.type === "charge.refunded") {
  await db.rpc("reverse_custody_deposit", { p_deposit_id, p_reason: event.type });
}
```
Se o deposit já tem coins committed > 0 e atletas gastaram: `reverse_custody_deposit` falha → notifica platform_admin + abre caso de `clearing_cases` para resolução manual.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.20).