---
id: L05-08
audit_ref: "5.8"
lens: 5
title: "Withdraw: nenhuma tela de progresso para pending→processing→completed"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "mobile", "portal", "cron", "reliability"]
files:
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/custody/withdraw/[id]/timeline/route.ts
  - supabase/migrations/20260421490000_l05_08_withdrawal_timeline.sql
  - tools/audit/check-withdrawal-timeline.ts
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs:
  - local:582867b
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Withdrawal progress is now a first-class DB primitive. Trigger
  on custody_withdrawals records every state transition into
  custody_withdrawal_events (append-only, (withdrawal_id, status)
  UNIQUE, RLS to admin_master of host group). The portal calls
  fn_withdrawal_timeline(uuid) to render a 4-step UI backed by
  canonical policy: expected_completion_at (SLA-derived),
  sla_breached flag, and refund_eta_days=2 on failed terminal
  state. Historical rows are backfilled via ON CONFLICT DO
  NOTHING. Ships with audit:withdrawal-timeline guard
  (26 invariants). The full async webhook rewrite remains wave-2
  scope; this patch provides the UI contract so the timeline
  renders correctly as soon as the async path ships.
---
# [L05-08] Withdraw: nenhuma tela de progresso para pending→processing→completed
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/custody/withdraw/route.ts` cria o withdraw e executa imediatamente. Para gateways assíncronos (PIX fim de semana), status fica em `processing` sem UI mostrando. Como [2.3], não há handler do callback.
## Risco / Impacto

— Admin fica sem feedback ("o dinheiro saiu ou não?") → abre ticket no suporte → custo operacional.

## Correção proposta

—

1. Trocar `execute_withdrawal` para retornar `{"status": "processing", "provider_ref": "..."}`.
2. Webhook do gateway atualiza para `completed|failed`.
3. Portal exibe timeline com 4 estados e "estimativa 10 min" / "estorno em até D+2 se falhar".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.8).