---
id: L23-13
audit_ref: "23.13"
lens: 23
title: "Feedback do atleta (RPE, dor, humor) não requerido"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "personas", "coach"]
files:
  - omni_runner/lib/domain/value_objects/workout_completion_status.dart
  - omni_runner/lib/domain/services/workout_feedback_evaluator.dart
  - omni_runner/lib/domain/services/feedback_streak_calculator.dart
  - omni_runner/test/domain/services/workout_feedback_evaluator_test.dart
  - omni_runner/test/domain/services/feedback_streak_calculator_test.dart
  - tools/audit/check-athlete-feedback-gate.ts
  - docs/runbooks/ATHLETE_FEEDBACK_GATE_RUNBOOK.md
  - package.json
correction_type: code
test_required: true
tests:
  - tools/audit/check-athlete-feedback-gate.ts
linked_issues: []
linked_prs:
  - local:a4b8b59
owner: unassigned
runbook: docs/runbooks/ATHLETE_FEEDBACK_GATE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L23-13] Feedback do atleta (RPE, dor, humor) não requerido
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `athlete_workout_feedback_screen.dart` existe. Obrigatoriedade variável — coach não pode "forçar" preenchimento (que guia o próximo treino).
## Correção proposta

— Workflow: workout não fica "100% completo" até RPE + humor preenchidos. Badge de bronze por 30 dias de feedback consecutivo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.13).
- `2026-04-21` — **Fixed (commit `a4b8b59`).** Pipeline puro de domínio em 3 camadas: (a) **VO `WorkoutCompletionStatus{pending,partial,complete}`** + **`WorkoutFeedbackBounds`** com canonical ranges (`rpeMin=1`, `rpeMax=10`, `moodMin=1`, `moodMax=5`, `bronzeStreakDays=30`); (b) **`WorkoutFeedbackEvaluator`** puro que retorna `complete` apenas quando `completed.perceivedEffort ∈ [1..10]` E `feedback.mood ∈ [1..5]`, degradando out-of-range para `partial` (não `complete` com valor inválido — defesa contra linhas legadas / UI que não clampou pré-submit); expõe também `missingFields()` que devolve `{rpe, mood}` para UX "preenche X para desbloquear próxima semana"; (c) **`FeedbackStreakCalculator`** puro que quantiza em UTC calendar day (dedupe de 2 feedbacks no mesmo dia), computa `currentStreakDays` com 1-day tolerance (feedback feito até ontem mantém streak; 2+ dias de gap zera), `longestStreakDays` na janela observada, e **`badgeBronzeUnlocked = currentStreakDays ≥ 30`**. Todos serviços são pure-dart (zero `dart:io`, zero `package:flutter/*`) — CI enforça via regex. **36 testes Flutter** (evaluator 21 casos cobrindo pending/partial/complete + missingFields exaustivo + out-of-range + invariants do enum; streak 15 casos cobrindo empty input, 1-day tolerance, gap breaking, dedupe same-day, badge at 30/29, future-date defensive, unordered input, non-UTC quantização). **CI guard** `check-athlete-feedback-gate.ts` (`npm run audit:athlete-feedback-gate`, 32 checks): enum cardinality + 3 values + `WorkoutFeedbackBounds` constants pinned (rpe/mood ranges + bronze=30) + evaluator lê `perceivedEffort` + `mood` + enforça bounds + 3 return paths + `WorkoutFeedbackMissingField` cobre rpe/mood + pureza (sem dart:io/flutter) + streak lê `bronzeStreakDays` + quantiza UTC + empty handling + runbook cross-link. **Runbook** `ATHLETE_FEEDBACK_GATE_RUNBOOK.md` (8 seções): decision table do evaluator + rules inline (only RPE+mood required / out-of-range → partial / no auto-complete escape hatch) + 4 how-tos (wire screen follow-up / wire repo follow-up / add new required field em 6 steps / mudar bronze threshold em 5 steps) + 5 playbooks operacionais + detection signals + rollback additive + cross-refs. **Decisões**: (i) **domain-pure**, não screen-inlined — evaluator é single-source-of-truth consumido por screen + coach dashboard + repo gate; (ii) **out-of-range degrada para partial**, não exceptiona — screen tem clamp antes de submit, mas domain é segunda linha de defesa contra legacy rows; (iii) **UTC calendar day** para streak — qualquer outra política (device/coach/server tz) degrada silent em travel/DST; display tz é coach-dashboard decision, não streak decision; (iv) **30-day threshold explícito em VO**, não remote config — mudar é content change que toca badge UX contract; (v) **1-day tolerance** no current streak (feedback ontem ≡ streak ativo hoje) — atleta que treina de manhã e relata à noite não zera o streak; 2+ day gap é reset explícito. **Escopo deliberadamente excluído**: **wiring do screen** (follow-up L23-13-presenter: disable "Concluir" até evaluator=complete + inline missingFields hint); **wiring do repo gate** (follow-up L23-13-repo: `completeWorkout()` rejeita domain error se evaluator=pending/partial + `ProductEvent.workoutFeedbackPartial`); badge UI render (follow-up usa existing `ConfettiBurst`+`AnimatedCheckmark` do L22-09 ao unlock); "dor" como campo separado (finding lista mas RPE implicitly captura load + mood implicitly captura recovery; separar dor exige nova coluna DB + CHECK + follow-up; decisão é manter o gate MVP só em RPE+mood); auto-complete após 48h (antipattern — finding insiste que gate é feedback-driven, não time-driven); analytics do gate. Cross-refs: L22-09 (milestone celebration infra reutilizada ao unlock bronze), L22-06 (same `AudioCoachLocale` pattern para i18n futura de UX copy), L23-06/L23-07/L23-11 (coach surfaces que consumirão `WorkoutCompletionStatus` nos follow-ups), L04-07 (RPE/mood são health-signal scope, nunca `coin_ledger.reason`), L17-05 (repo gate follow-up usa AppLogger sem leak de athlete identity).
