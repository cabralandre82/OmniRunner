# Time Trial Runbook

> **Finding:** [L23-14](../audit/findings/L23-14-corrida-de-teste-time-trial-agendada.md)
> **Guard:** `npm run audit:time-trial`
> **Pending cross-dep:** [L21-05](../audit/findings/L21-05-zonas-de-treino-pace-hr-nao-personalizaveis.md) — `athlete_zones` table

## 1. Why this exists

Coaches already prescribe 3 km / 5 km / 30-min time trials to
calibrate an athlete's threshold and zones, but the app had **no
workout type** for them and **no automation** to turn a TT result
into a threshold pace / LTHR update. The audit (L23-14) called this
out and asked for:

1. A workout type `time_trial` with special handling.
2. The result updating `athlete_zones` automatically.

L23-14 ships (1) and the domain primitives needed by (2). The actual
write into `athlete_zones` is a follow-up (`L23-14-zones`) pending
L21-05, which creates the `athlete_zones` table itself. Until then,
the `TimeTrialEstimate` object this module produces is ready to feed
the table as soon as it exists.

## 2. Invariants (CI-enforced)

| # | Invariant | Enforced by |
| - | --------- | ----------- |
| 1 | `TimeTrialProtocol` has exactly 3 values | CI + estimator test |
| 2 | Each protocol `kind` is a stable snake_case string (`three_km`, `five_km`, `thirty_minute`) | CI |
| 3 | `pacingMultiplier` is ≥ 1.00 for every protocol | CI + estimator test |
| 4 | 30-min TT multiplier is exactly 1.00 (it IS threshold) | CI |
| 5 | Freshness window is 84 days | CI + entity test |
| 6 | Estimator returns `invalid` (not throws) on corrupt input | estimator test |
| 7 | Scheduler pins `cycleType = 'test'` for all protocols | CI + scheduler test |
| 8 | Scheduler quantises `scheduledOn` to UTC day | CI + scheduler test |
| 9 | All domain files are pure (no flutter/dart:io imports) | CI |
| 10 | Runbook cross-links guard + finding + L21-05 | CI |

## 3. Protocol rationale

```
Protocol       kind            target         pace-multiplier  hr-multiplier
-------------  --------------  -------------  ---------------  -------------
3 km TT        three_km        3000 m         1.10             0.92
5 km TT        five_km         5000 m         1.05             0.95
30 min TT      thirty_minute   1800 s         1.00             1.00
```

**Why the multipliers**: lactate threshold is the pace an athlete can
sustain for ~60 minutes. A 30-min TT approximates it directly
(multiplier = 1.00). A 5 km TT is run ~5% hotter than threshold, so
threshold pace = TT pace × 1.05. A 3 km TT is ~10% hotter. These are
coaching consensus defaults; if a product decision moves any of them,
update:

1. The enum value in `time_trial_protocol.dart`.
2. The test `pacingMultiplier == 1.00` (or equivalent).
3. This table.
4. The finding note.

## 4. How-to

### 4.1 Wire the scheduler into the coach UI (follow-up L23-14-ui)

1. Coach selects a plan + date + one of the 3 protocols.
2. Call `TimeTrialScheduler.schedule(...)`.
3. Pass `TimeTrialScheduledWorkout.toPlanWorkoutPayload()` to the
   training-plan repo's `scheduleWorkout` path.
4. Persist `time_trial_kind` column (new follow-up migration) on
   `plan_workouts`.

### 4.2 Wire the estimator to `athlete_zones` (follow-up L23-14-zones, pending L21-05)

1. When a session finishes and its `plan_workouts.time_trial_kind`
   is non-null, construct a `TimeTrialResultEntity`.
2. Call `TimeTrialThresholdEstimator.estimate(result)`.
3. If `estimate.valid`, `UPSERT` into `athlete_zones`:
   - `threshold_pace_sec_km = estimate.thresholdPaceSecKm`
   - `lthr_bpm = estimate.lthrBpm`
   - `updated_by = 'auto_calculated'`
4. Emit `ProductEvent.timeTrialCompleted{protocol, threshold_pace}`.

### 4.3 Add a new protocol (e.g. 10-min TT)

1. Add the enum value with `kind` in snake_case.
2. Compute the pacing multiplier from coaching literature (3 min TT
   is ~120% of threshold, 10 min ~108%, etc.).
3. Add CI check for the new kind.
4. Extend §3 above.
5. Regression-test: the `every pacingMultiplier ≥ 1.00` check will
   catch accidental under-1 values.

## 5. Operational playbooks

### 5.1 Athlete says "threshold pace seems too slow"

Most common cause: estimator multiplied by 1.10 (3 km TT) when the
session was actually 5 km. Check `plan_workouts.time_trial_kind` for
that workout. If it was mis-scheduled as 3 km but the athlete ran 5
km, the multiplier is wrong. Fix: correct the `time_trial_kind` in
the plan row and re-trigger the zone update.

### 5.2 Estimator returns `invalid`

Three causes:

- `actualDistanceM` ≤ 0 (GPS dropped or session was saved before any
  distance accrued).
- `actualDurationS` ≤ 0 (clock issue, corrupted row).
- `avgPaceSecKm` computed to ≤ 0 (division of edge values).

`invalid` is intentional — the coach dashboard must not crash on a
single bad row. It shows the row as "needs re-test" and moves on.

### 5.3 CI guard fails

Read the first `[FAIL]` and branch:

- `TimeTrialProtocol.X declared` — someone renamed/removed a value;
  existing saved TT workouts would lose their protocol. Revert.
- `every pacingMultiplier ≥ 1.00` — someone set a multiplier < 1.
  That would produce threshold pace faster than TT pace (impossible).
- `scheduler pins cycleType = 'test'` — someone widened cycleType to
  'tempo' or similar. The periodization wizard (L23-06) and the TT
  flow both rely on `cycle_type='test'` to render the special UI.
- `runbook references L21-05 dependency` — someone forgot to keep
  the pending-dep link. Put it back; the follow-up sequencing needs it.

### 5.4 TT result older than 84 days shows up in zone update

Expected — the estimator produces an estimate, but the `isFreshOn()`
check on the entity is the gate the zone-updater uses. Do NOT feed
stale estimates into `athlete_zones`; the athlete has drifted and
needs a re-test.

## 6. Detection signals

| Signal | Source | Action |
| ------ | ------ | ------ |
| `[FAIL]` in `npm run audit:time-trial` | CI | Block merge |
| `flutter test` failure | CI | Block merge |
| `ProductEvent.timeTrialCompleted` drops to zero | PostHog | UI stopped wiring results |
| Coach filing "zones didn't update after re-test" | Support | §5.1 or §5.4 |

## 7. Rollback

Fully additive. The 4 new domain files (protocol VO + entity + 2
services) are opt-in:

- `domain/value_objects/time_trial_protocol.dart`
- `domain/entities/time_trial_result_entity.dart`
- `domain/services/time_trial_threshold_estimator.dart`
- `domain/services/time_trial_scheduler.dart`

Revert the commit; no DB migration to reverse; no existing callers
today. The coach-UI follow-up (L23-14-ui) is the pivot; its own PR
handles rollback for the UI surface.

## 8. Cross-references

- **L21-05** (pending, Wave 0 critical) — creates `athlete_zones`;
  the `L23-14-zones` follow-up lands the updater as soon as this ships.
- **L23-06** — periodization wizard; the `cycle_type='test'` enum
  value is shared, so this runbook MUST stay aligned with
  `PERIODIZATION_WIZARD_RUNBOOK.md`.
- **L23-07 / L23-11** — coach dashboards consume TT results via the
  existing session aggregation; no direct change needed until the
  zone updater lands.
- **L23-13** — workout feedback gate; TT workouts inherit the same
  RPE + mood requirement. Post-TT feedback is especially valuable
  because it reveals whether the athlete went out too hot.
- **L17-05** — when the zone updater lands, its failures (e.g. no HR
  strap) must flow through `AppLogger.warn` and not crash the session
  submission.
