---
id: L02-06
audit_ref: "2.6"
lens: 2
title: "execute_withdrawal — Estado 'processing' sem transição final"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "migration", "cron", "ux"]
files:
  - portal/src/app/api/custody/withdraw/route.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L02-06] execute_withdrawal — Estado 'processing' sem transição final
> **Lente:** 2 — CTO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** BACKEND + PORTAL
**Personas impactadas:** Assessoria (admin_master)
## Achado
`20260228170000:125-127` seta `status='processing'` mas **nenhuma migration posterior adiciona transição para `'completed'`/`'failed'`**. O fluxo é: `pending → processing` (in-RPC) → ??? (fora do sistema). `portal/src/app/api/custody/withdraw/route.ts:104` chama `executeWithdrawal` e retorna a withdrawal — mas na prática a saída de USD para o banco local é manual (TED externo), sem nenhum mecanismo que marque `completed`.
## Risco / Impacto

Withdrawals ficam eternamente em `processing`. Reconciliação impossível via `getWithdrawals()`. Se o TED externo falhar, a assessoria não recupera os USD (foram debitados de `total_deposited_usd`).

## Correção proposta

1. Criar endpoint `POST /api/platform/custody/withdrawal/[id]/complete` (platform_admin) que seta `status='completed'` + `completed_at=now()` + `payout_reference=` (código do TED).
  2. Criar endpoint `/fail` que reverte `total_deposited_usd += amount_usd` (precisa de RPC atômica `reverse_withdrawal`).
  3. Cron `stale-withdrawals` alerta platform_admin se uma withdrawal fica > 7 dias em processing.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.6).