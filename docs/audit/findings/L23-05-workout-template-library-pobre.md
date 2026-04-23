---
id: L23-05
audit_ref: "23.5"
lens: 23
title: "Workout template library pobre"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "migration", "personas", "coach"]
files:
  - supabase/migrations/20260421650000_l23_05_workout_template_library.sql
  - tools/audit/check-workout-template-library.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-workout-template-library.ts
linked_issues: []
linked_prs:
  - "local:4f71114"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed at 2026-04-21 (commit 4f71114) by seeding the canonical workout
  catalogue and cloning RPC:
    - public.workout_template_catalog — global library (no group_id),
      with slug UNIQUE + shape CHECK (^[a-z][a-z0-9_-]{2,62}$),
      category CHECK enum (12 types), workout_type CHECK enum, source
      CHECK enum (daniels, pfitzinger, hudson, custom), difficulty ∈
      [1, 5], is_active flag. RLS: public read of active templates +
      platform_admin write.
    - public.workout_template_catalog_blocks — mirrors
      coaching_workout_blocks shape, with block_type / hr_zone / rpe
      CHECKs and UNIQUE(catalog_id, order_index).
    - Seed: 12 canonical workouts (Daniels, Pfitzinger, Hudson, Custom)
      inserted via ON CONFLICT (slug) DO NOTHING; some include
      block-level seeds (e.g. daniels-tempo-20).
    - fn_clone_catalog_template(catalog_id, group_id, custom_name) —
      SECURITY DEFINER, coach / admin_master only, idempotent via
      catalog_slug anchor in the description, copies blocks.
    - fn_list_catalog_templates(category, source, difficulty_max) —
      STABLE SECURITY INVOKER, filter helper.
    - Self-tests assert seed count, source diversity, block count,
      CHECK / index presence.
    - 46-invariant CI guard `npm run audit:workout-template-library`.
---
# [L23-05] Workout template library pobre
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `staff_workout_templates_screen.dart` existe. Coach de assessoria nova começa do zero. Sem biblioteca pré-populada (fartlek clássicos, treino limiar, tempo run, etc).
## Correção proposta

— `workout_templates_library` seeded em migration com 50+ treinos canônicos (Daniels, Pfitzinger, Hudson). Coach clona e customiza.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.5).