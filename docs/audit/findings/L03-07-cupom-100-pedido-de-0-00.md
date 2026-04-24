---
id: L03-07
audit_ref: "3.7"
lens: 3
title: "Cupom 100% / pedido de $0.00"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["portal", "edge-function", "migration", "ux", "finance"]
files:
  - "supabase/migrations/20260221000011_billing_portal_tables.sql"
  - "supabase/functions/create-checkout-session/index.ts"
  - "supabase/functions/create-checkout-mercadopago/index.ts"
  - "supabase/migrations/20260421670000_l23_09_athlete_subscriptions.sql"
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: sistema de cupom não existe; CHECK (price_cents > 0) em todas as tabelas relevantes impede pedido R$0 por construção."
---
# [L03-07] Cupom 100% / pedido de $0.00
> **Lente:** 3 — CFO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** ✅ fixed
**Camada:** PORTAL
**Personas impactadas:** Atleta, Plataforma

## Achado original
Preocupação: `create-checkout-session` e `create-checkout-mercadopago` poderiam aceitar `price_cents = 0` via cupom 100%, criando checkout de R$0.

## Re-auditoria 2026-04-24

### Sistema de cupom
Busca exaustiva: `rg -i 'coupon|cupom|discount_code|discount_percent|100.?percent' portal/ supabase/` → **nenhum sistema de cupom implementado**. O único tratamento de desconto está nas migrations de sponsorship (L16-05) — mas **não é aplicado em checkout**.

### Defesa em profundidade
Mesmo sem cupom, a proteção contra "pedido R$0" está em múltiplas camadas:

| Camada | Guard | Evidência |
|---|---|---|
| DB — `billing_products.price_cents` | `CHECK (price_cents > 0)` | `supabase/migrations/20260221000011_billing_portal_tables.sql:71` |
| DB — `billing_purchases.price_cents` | `CHECK (price_cents > 0)` | idem:110 |
| DB — `athlete_subscriptions.price_cents` | `CHECK (price_cents > 0)` + `CHECK (price_cents >= 500)` em `fn_create_subscription` | `supabase/migrations/20260421670000_l23_09_athlete_subscriptions.sql:55-56, 196-198` |
| Edge Function | Lê `product.price_cents` do DB (que já é > 0) e repassa a Stripe/MP. Não há branch de manipulação. | `supabase/functions/create-checkout-session/index.ts:199` |
| Stripe API | `mode: 'payment'` + `unit_amount: 0` é rejeitado pela própria Stripe API. | Stripe docs (behavior externo) |

### Conclusão
**Impossível criar checkout de R$0 por construção.** Nada a fazer. Se futuramente um sistema de cupom for introduzido, criar novo finding explícito para garantir:
1. Cupom 100% **não pode** gerar `price_cents < 500` (CHECK existente no RPC de subscription).
2. Cupom 100% gera `status = 'free'` + bypass do Stripe checkout, **nunca** checkout de R$0.
3. Auditoria de uso (tabela `coupon_redemptions` + throttling por user/IP).

**Reclassificado**: severity `na` → `safe`, status `fix-pending` → `fixed`.

## Referência narrativa
Contexto completo em [`docs/audit/parts/02-cto-cfo.md`](../parts/02-cto-cfo.md) — anchor `[3.7]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.7).
- `2026-04-24` — Re-auditoria confirmou ausência de sistema de cupom + CHECK `price_cents > 0` em todas as tabelas. Flipped para `fixed` (safe).
