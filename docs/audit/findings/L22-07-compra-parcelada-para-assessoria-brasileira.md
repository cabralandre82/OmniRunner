---
id: L22-07
audit_ref: "22.7"
lens: 22
title: "Compra parcelada para assessoria brasileira"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["migration", "personas", "athlete-amateur"]
files:
  - supabase/migrations/20260421640000_l22_07_installments.sql
  - tools/audit/check-installments-br.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-installments-br.ts
linked_issues: []
linked_prs:
  - "local:56b1dfd"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed at 2026-04-21 (commit 56b1dfd) by shipping the canonical SQL schema
  for BR installment plans + per-group gateway preference:
    - public.billing_gateway_preferences (admin_master write, coach read).
    - fn_recommend_gateway(country_code) IMMUTABLE PARALLEL SAFE —
      'asaas' for 'BR', 'stripe' otherwise (NULL included).
    - fn_validate_installment_config(count, total_cents) IMMUTABLE PARALLEL
      SAFE — enforces count ∈ [1, 12], total_cents > 0, and minimum R$ 5,00
      per installment.
    - public.billing_installment_plans (header, unique on purchase_id, state
      machine active → completed / cancelled with CHECK on gateway,
      payment_method, validity, terminal timestamps).
    - public.billing_installments (state pending → paid / overdue /
      cancelled, unique (plan_id, sequence_no), partial index on
      (due_date) WHERE status='pending' for overdue sweeps).
    - fn_create_installment_plan (admin-only, atomic schedule generation,
      cents-exact distribution with remainder on first installment).
    - fn_mark_installment_paid (service-role, idempotent, promotes plan to
      completed when all installments are paid; FOR UPDATE).
    - fn_mark_installments_overdue (service-role cron target).
    - fn_cancel_installment_plan (admin-only, cascades pending + overdue).
    - Self-tests assert gateway recommender, config validator, schema
      CHECKs, and index presence.
    - 57-invariant CI guard `npm run audit:installments-br`.
---
# [L22-07] Compra parcelada para assessoria brasileira
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Asaas suporta boleto/PIX parcelado. Stripe apenas cartão. Realidade BR: 60% prefere pagar parcelado/PIX.
## Correção proposta

— Gateway preference: default Asaas para BR; Stripe para internacional. Checkout mostra opções "PIX R$ 120/mês" vs "Cartão 10× R$ 12,50". Já tem módulo billing — confirmar integração ativa.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.7).