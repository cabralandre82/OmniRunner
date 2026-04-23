---
id: L23-12
audit_ref: "23.12"
lens: 23
title: "Onboarding de novo atleta no clube"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["integration", "personas", "coach"]
files:
  - omni_runner/lib/domain/value_objects/athlete_onboarding_step.dart
  - omni_runner/lib/domain/entities/athlete_onboarding_state.dart
  - omni_runner/lib/domain/services/athlete_onboarding_service.dart
  - tools/audit/check-athlete-onboarding.ts
  - docs/runbooks/ATHLETE_ONBOARDING_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/services/athlete_onboarding_service_test.dart
  - tools/audit/check-athlete-onboarding.ts
linked_issues: []
linked_prs:
  - local:6889042
owner: audit-bot
runbook: docs/runbooks/ATHLETE_ONBOARDING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Pure-domain state machine shipped (enum, VO, service). Persistence (coaching_onboarding_state), wizard UI, Strava backfill Edge Function and email nudges are tracked follow-ups (L23-12-persistence, L23-12-wizard, L23-12-strava-backfill, L23-12-email-nudges)."
---
# [L23-12] Onboarding de novo atleta no clube
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach cadastra atleta → atleta recebe convite email. Sem wizard "importe histórico Strava, configuramos zonas".
## Correção proposta

— Convite com "após login, vamos importar seu Strava dos últimos 6 meses (opcional) para personalizarmos seu plano."

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.12).
- `2026-04-21` — **Resolvido** (commit `6889042`). Shipped pure-Dart state machine (`AthleteOnboardingStep` enum de 6 valores com wire strings estáveis, `StravaImportChoice` enum que força decisão explícita `imported|skipped`, `AthleteOnboardingService` stateless com transições one-way forward, `nudgeFor()` que resolve categoria de nudge por step, `AthleteOnboardingBounds` pinando `staleInviteDays=14` / `stalledProfileDays=3`). 29 flutter_test cases + guard TS com 56 invariantes (`npm run audit:athlete-onboarding`) + runbook. Follow-ups: `L23-12-persistence` (tabela/coluna), `L23-12-wizard` (UI Flutter), `L23-12-strava-backfill` (Edge Function puxando 6 meses), `L23-12-email-nudges` (L15-04 templates por categoria).