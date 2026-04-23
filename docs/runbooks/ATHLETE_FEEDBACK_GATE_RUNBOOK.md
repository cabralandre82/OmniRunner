# Athlete Feedback Gate Runbook

> **Finding:** [L23-13](../audit/findings/L23-13-feedback-do-atleta-rpe-dor-humor-nao-requerido.md)
> **Guard:** `npm run audit:athlete-feedback-gate`
> **Locale/i18n cross-ref:** [L22-06](../audit/findings/L22-06-voice-coaching-parcial.md)

## 1. Why this exists

The athlete workout-feedback screen already existed
(`athlete_workout_feedback_screen.dart`) but **nothing was required**.
An athlete could mark a workout finished with RPE and mood left blank,
and the coach's prescription for the next week had to proceed without
signal. The audit (L23-13) called this out: "coach não pode forçar
preenchimento (que guia o próximo treino)".

The fix is deliberately **pure domain, not UI**:

- A value object (`WorkoutCompletionStatus`) defines the three states
  an athlete workout can be in: `pending` / `partial` / `complete`.
- A pure evaluator (`WorkoutFeedbackEvaluator`) is the sole decider of
  "is this workout complete?". The UI and the coach surface both read
  from it. If the rule ever changes ("also require sleep_hours", say),
  it changes in exactly one place.
- A pure streak calculator (`FeedbackStreakCalculator`) counts
  consecutive UTC calendar days of *complete* feedback and exposes a
  `badgeBronzeUnlocked` flag for 30 consecutive days (the bronze
  badge the finding's proposal specified).

The presenter/screen wire-up is a deliberate follow-up
(`L23-13-presenter`) — see §4.

## 2. Invariants (CI-enforced)

| # | Invariant | Enforced by |
| - | --------- | ----------- |
| 1 | `WorkoutCompletionStatus` has exactly 3 values (`pending`, `partial`, `complete`) | CI guard + enum test |
| 2 | RPE required range is [1, 10] (`rpeMin`/`rpeMax`) | CI guard + evaluator test |
| 3 | Mood required range is [1, 5] (`moodMin`/`moodMax`) | CI guard + evaluator test |
| 4 | Bronze streak threshold is 30 days (`bronzeStreakDays`) | CI guard + streak test |
| 5 | `WorkoutFeedbackEvaluator` reads `perceivedEffort` AND `mood` before calling `complete` | CI guard + evaluator tests |
| 6 | Out-of-range values degrade to `partial`, not `complete` | evaluator tests |
| 7 | `FeedbackStreakCalculator` quantises to UTC calendar day | CI guard + streak test |
| 8 | Evaluator + streak calc are platform-pure (no `dart:io`, no `package:flutter/*`) | CI guard |
| 9 | Runbook cross-links guard + finding | CI guard |

## 3. How the evaluator decides

```
evaluate(completed, feedback):
  if completed == null:
    return pending               # athlete hasn't finished the workout
  rpe_valid   = 1 ≤ completed.perceivedEffort ≤ 10
  mood_valid  = 1 ≤ feedback?.mood            ≤ 5
  if rpe_valid and mood_valid:
    return complete              # unblocks coach's next-week pipeline
  return partial                 # block "completo" badge, keep asking
```

Rationale:

- **Only RPE + mood are required.** The finding called out *feedback*
  (RPE, dor, humor). Rating (of the workout itself) and free-text
  notes stay optional because they are trainer/athlete-specific polish,
  not signal for load modulation.
- **Out-of-range ⇒ partial, not complete.** Stale rows or racey UI
  drift could carry values outside [1..10] or [1..5]. The evaluator
  treats those as missing — the UI is expected to clamp before
  submit, and the domain is the second line of defense.
- **No "auto-complete after 48h" escape hatch.** Intentional: the
  finding's whole point is that feedback must be the gate, not time.
  If a product experiment later decides to auto-`complete` after N
  days, it must do so by writing the RPE/mood values (not by
  bypassing the evaluator).

## 4. How-to

### 4.1 Wire the gate into the feedback screen (follow-up L23-13-presenter)

1. Import `WorkoutFeedbackEvaluator` into
   `athlete_workout_feedback_screen.dart`.
2. Disable the "Concluir treino" button until
   `evaluator.evaluate(...) == WorkoutCompletionStatus.complete`.
3. Show `evaluator.missingFields(...)` inline ("Preenche RPE e humor
   para liberar o próximo treino").
4. Call `submitFeedback()` + `completeWorkout()` only on complete
   status — the repository contract will refuse otherwise (§4.2).

### 4.2 Wire the gate into the plan repository

The existing `ITrainingPlanRepo.completeWorkout` has no feedback gate.
Follow-up L23-13-repo will:

1. Load the latest `CompletedWorkoutSummary` and `WorkoutFeedbackSummary`.
2. Reject `completeWorkout()` with a domain error if the evaluator
   returns `pending` or `partial`.
3. Emit a `ProductEvent.workoutFeedbackPartial` analytics event with
   the missing fields.

### 4.3 Add a new required field (e.g. sleep hours)

1. Add the column to the DB + DTO + `WorkoutFeedbackSummary`.
2. Extend `WorkoutFeedbackBounds` with the new range constants.
3. Extend `WorkoutFeedbackEvaluator.evaluate()` with the new check —
   it must participate in the `partial` ⇒ `complete` upgrade.
4. Add the new value to `WorkoutFeedbackMissingField` enum.
5. Extend `check-athlete-feedback-gate.ts` with a
   `"evaluator enforces <field>"` check so a future regression fails
   the build.
6. Update §3 above.

DO NOT add the field without also updating the CI guard — the whole
point of L23-13 is that the gate is enforced, not hoped for.

### 4.4 Change the bronze-streak threshold

Tempting to move 30→21 or 30→60 based on product data. If you do:

1. Change `WorkoutFeedbackBounds.bronzeStreakDays`.
2. Change the CI guard's
   `WorkoutFeedbackBounds.bronzeStreakDays == 30` check.
3. Change the test expecting `badgeBronzeUnlocked` at 30.
4. Update §2 above and the finding's fixed_at note.
5. Coordinate with badge/reward surfaces — the change renames the
   badge's UX contract with athletes who currently see "30 dias para
   o bronze".

## 5. Operational playbooks

### 5.1 Athlete complains "marquei como concluído e não sumiu"

Expected, by design. The evaluator is likely returning `partial`:

1. Dump `completedWorkout.perceivedEffort` and `feedback.mood` for
   the workout.
2. If either is `null` or out of range, the athlete did not actually
   fill the required fields; the UI should already show the pending
   banner.
3. If both look valid, check for locale drift (old app version
   carrying stale DTO mapping) — force-update threshold applies.

### 5.2 Coach complains "atleta diz que preencheu mas meu dashboard bloqueia"

Same as §5.1 from the coach side: read the stored
`completedWorkout.perceivedEffort` + `feedback.mood`. If nulls,
either (a) the athlete saved a partial draft without submit, or (b)
an older client bypassed the evaluator (this is why L23-13-repo
follow-up adds a server-side gate).

### 5.3 CI guard fails

Read the first `[FAIL]` and branch:

- `WorkoutCompletionStatus.*` missing → someone renamed a value; the
  UI `switch` will compile-error, DO NOT "fix" by removing the guard.
- `rpeMin == 1` / `rpeMax == 10` changed → confirm with product,
  then follow §4.4's update path.
- `evaluator reads perceivedEffort` / `evaluator reads mood` failed
  → someone removed the requirement. That is the audit finding's
  *exact* regression; revert.
- `evaluator is pure` failed → someone imported `dart:io` or
  `package:flutter/*` into the domain layer. Extract the impure work
  to a gateway in `data/`, keep `domain/` pure.

### 5.4 Streak shows inflated numbers

Most common cause: presenter is passing *all* feedback dates (including
`partial` ones) instead of filtering to `complete`. The evaluator is
upstream of the streak calc; feed the calc only dates where
`evaluate() == complete`. The streak calc dedupes same-UTC-day inputs
so accidental duplicates don't inflate the count.

### 5.5 Timezone drift in streaks

The calc quantises to UTC day. An athlete in BRT (UTC-3) who trains at
22:00 local on Monday lands as Tuesday UTC. This is intentional — any
other policy (device timezone, coach timezone, server timezone)
degrades silently across travel or DST. If coaches push back, the fix
is a *display* timezone on the coach dashboard, not a different
quantisation in the calc.

## 6. Detection signals

| Signal | Source | Action |
| ------ | ------ | ------ |
| `[FAIL]` in `npm run audit:athlete-feedback-gate` | CI | Block merge |
| `flutter test` failure in `workout_feedback_evaluator_test.dart` | CI | Block merge |
| `ProductEvent.workoutFeedbackPartial` spike | PostHog | Product: is the ask clear in UI? |
| Athletes filing "completo" but coach dashboard shows partial | Support | §5.1 / §5.2 |
| Bronze-badge grants drop to 0 | PostHog | §5.4 / §5.5 |

## 7. Rollback

Fully additive. The three new files are opt-in:

- `domain/value_objects/workout_completion_status.dart`
- `domain/services/workout_feedback_evaluator.dart`
- `domain/services/feedback_streak_calculator.dart`

Zero existing callers today. Revert the commit to fully rollback; no
data cleanup needed. The screen change (follow-up L23-13-presenter) is
where the user-visible gate lands; that PR is the rollback pivot.

## 8. Cross-references

- **L22-09** — milestone celebration ships the "congratulations"
  beat; this gate is the sibling "come back and finish" beat.
- **L22-06** — same `AudioCoachLocale` pattern informs future i18n of
  the UX copy shown on partial status.
- **L23-06 / L23-07 / L23-11** — the coach surfaces whose next-week
  decisions depend on complete feedback; they will start consuming
  `WorkoutCompletionStatus` in their respective follow-ups.
- **L04-07** — RPE/mood are health-signal scope; they stay in the
  plan-workout surface, never in `coin_ledger.reason`.
- **L17-05** — repository-side gate (follow-up) routes its domain
  error through AppLogger without leaking athlete identity in the
  message.
