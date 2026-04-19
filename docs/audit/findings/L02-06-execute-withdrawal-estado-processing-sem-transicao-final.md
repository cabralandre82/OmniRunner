---
id: L02-06
audit_ref: "2.6"
lens: 2
title: "execute_withdrawal — Estado 'processing' sem transição final"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "mobile", "portal", "migration", "cron", "ux"]
files:
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/platform/custody/withdrawals/[id]/complete/route.ts
  - portal/src/app/api/platform/custody/withdrawals/[id]/fail/route.ts
  - supabase/migrations/20260419150000_l02_withdrawal_lifecycle_completion.sql
correction_type: process
test_required: true
tests:
  - portal/src/app/api/platform/custody/withdrawals/[id]/complete/route.test.ts
  - portal/src/app/api/platform/custody/withdrawals/[id]/fail/route.test.ts
linked_issues: []
linked_prs:
  - "commit:fd8fd1a"
owner: backend
runbook: docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fechado em três camadas:

  1. **Database** (`20260419150000_l02_withdrawal_lifecycle_completion.sql`):
     - `complete_withdrawal(p_id, p_payout_reference, p_actor, p_note)`
       — `processing → completed` idempotente (re-clique devolve
       `was_terminal=true`). Escreve `portal_audit_log` com a
       `payout_reference` antiga preservada.
     - `fail_withdrawal(p_id, p_reason, p_actor)` — `processing →
       failed` atômico: refunda `total_deposited_usd`, deleta a linha
       `platform_revenue` de `fee_type='fx_spread'` ligada à
       withdrawal, e re-valida `check_custody_invariants()` na MESMA
       transação (aborta P0008 se o estorno desbalancearia a custody).
     - `fn_stale_withdrawals(p_threshold_hours int default 168)` —
       diagnóstico read-only usado pelo runbook e pelo cron de alerta.
     - `fn_alert_stale_withdrawals_safe()` + cron pg `stale-withdrawals-alert`
       em `45 6 * * *` UTC, encapsulado no padrão L12-03
       (`fn_cron_should_run` / `fn_cron_mark_*` + advisory lock).
       Emite `RAISE NOTICE '[L02-06.alert] ...'` quando há ≥1 saque
       `processing` há > 7 dias — log-shipper roteia para Sentry/Slack
       conforme `docs/runbooks/ALERT_POLICY.md`.

  2. **Portal** (`/api/platform/custody/withdrawals/[id]/{complete,fail}`):
     - Auth: `profiles.platform_role = 'admin'` (padrão canônico do
       projeto, não a tabela hipotética `platform_admins` ainda
       presente em duas rotas legadas).
     - Idempotência ponta-a-ponta: `withIdempotency()` (L18-02)
       embrulha o RPC para que retries de rede / double-click não
       criem dois eventos no `portal_audit_log` mesmo nos casos onde
       o RPC subjacente já é idempotente.
     - Mapeamento de erros:
       - `P0002 / WITHDRAWAL_NOT_FOUND` → 404 NOT_FOUND
       - `P0008 / INVALID_TRANSITION` → 409 INVALID_TRANSITION
       - `P0008 / INVARIANT_VIOLATION` → 409 INVARIANT_VIOLATION (com
         hint para `WITHDRAW_STUCK_RUNBOOK §3.3` fallback manual)
       - `P0001` (validação) → 400 VALIDATION_FAILED
     - `auditLog()` só dispara quando `was_terminal=false` para evitar
       duplicar trilha em re-cliques.

  3. **Runbook**: `WITHDRAW_STUCK_RUNBOOK.md` ganhou §3.0 (apontando
     para o endpoint canônico) preservando o SQL bruto como fallback
     last-resort para incidentes onde o portal está fora.

  Cobertura: 23 testes vitest (12 complete + 11 fail) cobrindo auth,
  validação, idempotência, mapping de erros do RPC, audit log
  condicional. Suite portal: 1108 testes verdes (de 1085). Audit
  verifier: 348/348 OK.
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
- `2026-04-19` — **Fixed**: migration `20260419150000_l02_withdrawal_lifecycle_completion.sql`
  adiciona `complete_withdrawal`, `fail_withdrawal`, `fn_stale_withdrawals`,
  cron diário `stale-withdrawals-alert` (L12-03 wrapper). Portal expõe
  `POST /api/platform/custody/withdrawals/[id]/{complete,fail}`
  (platform_admin, idempotente via L18-02). Runbook
  WITHDRAW_STUCK atualizado com §3.0 apontando ao endpoint canônico.