---
id: L03-15
audit_ref: "3.15"
lens: 3
title: "Pedido eternamente pendente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "webhook", "cron", "fixed"]
files:
  - supabase/migrations/20260421840000_l03_15_expire_stale_deposits.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - "supabase/migrations/20260421840000_l03_15_expire_stale_deposits.sql (in-migration self-test)"
  - "npm run audit:k2-sql-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — new RPC fn_expire_stale_deposits(p_max_age interval default
  '48 hours'). Adds 'expired' to custody_deposits.status CHECK +
  expired_at column + partial index on pending. pg_cron job
  l03_15_expire_stale_deposits fires daily at 03:10 UTC (idempotent via
  cron.job lookup). The expired transition NEVER touches coin_ledger or
  wallets — the deposit had not yet been credited.
---
# [L03-15] Pedido eternamente pendente
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Atleta
## Achado
`custody_deposits.status='pending'` sem cron que expira. Em casos reais, Stripe pode enviar webhook muito depois, ou nunca.
## Correção proposta

Cron `expire-stale-deposits` que marca `status='expired'` após 48h sem confirmação. Separar de `refunded` (que exige ação explícita).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.15).