---
id: L23-09
audit_ref: "23.9"
lens: 23
title: "Billing integrado (cobrança de mensalidade aos atletas)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "ux", "reliability", "personas", "coach"]
files:
  - supabase/migrations/20260421670000_l23_09_athlete_subscriptions.sql
  - tools/audit/check-athlete-subscriptions.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-athlete-subscriptions.ts
linked_issues: []
linked_prs:
  - "local:b063aab"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed at 2026-04-21 (commit b063aab) by shipping the per-athlete
  monthly subscription + invoice schema so the coletivo loop (athlete
  pays → group custody credit → staff withdrawal) can close end-to-end:
    - public.athlete_subscriptions — (group, athlete) contract with
      price_cents, billing_day_of_month ∈ [1, 28], gateway ∈
      {asaas, stripe, mercadopago}, 3-state machine (active / paused /
      cancelled) with CHECK state_timestamps biconditional. Partial
      unique index blocks duplicate active subscriptions. RLS:
      athlete-self + group staff read.
    - public.athlete_subscription_invoices — one row per (subscription,
      period_month) via UNIQUE index, status ∈ {pending, paid, overdue,
      cancelled}, biconditional paid_timestamp + cancelled_timestamp
      CHECKs. period_first_of_month CHECK. Partial status+due index.
    - fn_subscription_start (admin-only, enforces coach/admin_master,
      athlete membership, R$ 5,00 floor, day range).
    - fn_subscription_pause (admin-only, rejects non-active).
    - fn_subscription_cancel (athlete-self OR group staff, cascades
      pending invoices to cancelled).
    - fn_subscription_generate_cycle (service-role cron, idempotent via
      ON CONFLICT).
    - fn_subscription_mark_invoice_paid (service-role, idempotent on
      paid, emits outbox event subscription.invoice.paid guarded by
      to_regproc + fail-open so the coin-credit pipeline can consume
      asynchronously).
    - fn_subscription_mark_overdue (service-role sweep).
    - 56-invariant CI guard `npm run audit:athlete-subscriptions`.
---
# [L23-09] Billing integrado (cobrança de mensalidade aos atletas)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `billing` module + Asaas existem. Coach consegue cobrar atletas via produto? Fluxo Asaas → custódia ([9.8]) → pagamento de staff? Ciclo inteiro de ROI não auditado.
## Correção proposta

— E2E: atleta paga R$ 200 via Asaas → vira coins na custody da assessoria → coach distribui moedas como bônus → saca via withdraw. Se não existe, é **oportunidade gigante** perdida.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.9).