---
id: L22-09
audit_ref: "22.9"
lens: 22
title: "Progress celebration tímida"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "personas", "athlete-amateur"]
files:
  - omni_runner/lib/domain/value_objects/milestone_kind.dart
  - omni_runner/lib/domain/entities/milestone_entity.dart
  - omni_runner/lib/domain/services/milestone_detector.dart
  - omni_runner/lib/domain/services/milestone_copy_builder.dart
  - omni_runner/lib/presentation/widgets/success_overlay.dart
  - tools/audit/check-milestone-celebration.ts
  - docs/runbooks/CELEBRATION_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/services/milestone_detector_test.dart
  - omni_runner/test/domain/services/milestone_copy_builder_test.dart
linked_issues: []
linked_prs:
  - "local:e41d5d4"
owner: unassigned
runbook: docs/runbooks/CELEBRATION_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Pure milestone detector (9 kinds) + locale copy (pt-BR/en/es) + CI guard. Confetti widget (success_overlay.dart) pre-existed; this wires the when, not the how."
---
# [L22-09] Progress celebration tímida
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Primeira corrida completa, primeira semana, primeira 5K — sem celebração visual (confete, animação).
## Correção proposta

— Moments milestone com animação (`flutter_confetti`, lottie) + compartilhamento OG ([15.3]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.9).