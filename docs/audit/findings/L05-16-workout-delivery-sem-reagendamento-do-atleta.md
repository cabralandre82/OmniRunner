---
id: L05-16
audit_ref: "5.16"
lens: 5
title: "Workout delivery: sem reagendamento do atleta"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["ux", "delivery", "fixed"]
files:
  - supabase/migrations/20260421810000_l05_16_workout_reschedule.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - supabase/migrations/20260421810000_l05_16_workout_reschedule.sql
linked_issues: []
linked_prs:
  - aa816fb
  - 8c62f60
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — athlete-initiated reschedule flow:
    • workout_delivery_items gains athlete_requested_date + _at + _reason
      and coach_response/_at/_by columns.
    • fn_request_reschedule(item_id, new_date, reason) — athlete-only,
      auth.uid() must equal item.athlete_user_id, item.status pending|published.
    • fn_resolve_reschedule(item_id, decision) — group staff only
      (admin_master | coach | assistant), decision accepted|rejected.
  Both RPCs are SECURITY DEFINER with explicit role checks (P0010) and
  log to workout_delivery_events for audit trail.
---
# [L05-16] Workout delivery: sem reagendamento do atleta
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `workout_delivery_items` permite coach marcar "treino de hoje". Atleta machuca tornozelo, precisa mover para amanhã. Não há endpoint/UI.
## Correção proposta

— Campo `athlete_requested_date date` + fluxo de aceite do coach (notificação push).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.16).