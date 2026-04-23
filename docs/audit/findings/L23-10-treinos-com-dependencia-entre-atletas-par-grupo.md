---
id: L23-10
audit_ref: "23.10"
lens: 23
title: "Treinos com dependência entre atletas (par/grupo)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["cron", "personas", "coach"]
files:
  - supabase/migrations/20260421680000_l23_10_paired_workouts.sql
  - tools/audit/check-paired-workouts.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-paired-workouts.ts
linked_issues: []
linked_prs:
  - "local:d4c4a21"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed at 2026-04-21 (commit d4c4a21) by introducing the pairing
  aggregate on top of coaching_workout_assignments:
    - public.coaching_workout_pairings (group_id, scheduled_date,
      title, min_confirmations ∈ [2, 20], 5-state machine
      pending → partially_confirmed → all_confirmed → completed /
      dissolved) with biconditional dissolved_timestamp /
      completed_timestamp CHECKs.
    - public.coaching_workout_pairing_members — join with
      confirmation_status ∈ {pending, confirmed, declined},
      responded_at, decline_reason. CHECK responded_timestamp
      biconditional, decline_has_reason_shape enforces reason
      length on decline. Unique indexes on assignment_id
      (no assignment in two pairings) and (pairing, athlete).
    - fn_pairing_recompute_status — pure aggregation helper with
      priority completed > dissolved > all_confirmed >
      partially_confirmed > pending. Stamps transition timestamps.
    - fn_pairing_create (admin-only, 2-20 assignments, share
      group + date, refuses assignments already paired with
      23505 unique_violation).
    - fn_pairing_respond (athlete-self, FOR UPDATE to serialize,
      refuses terminal pairings with P0005, emits
      workout.pairing.partner_declined outbox event on decline
      guarded by to_regproc + fail-open so mobile clients can
      notify the remaining partners).
    - Self-tests assert pairings status_check, dissolved_timestamp
      CHECK, responded_timestamp CHECK, assignment uniq index.
    - 50-invariant CI guard `npm run audit:paired-workouts`.
---
# [L23-10] Treinos com dependência entre atletas (par/grupo)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— "João e Maria correm juntos amanhã, 10 km ritmo base". Hoje são dois workouts separados.
## Correção proposta

— `paired_workouts` tipo com sincronização: se um não confirmar, o outro é avisado.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.10).