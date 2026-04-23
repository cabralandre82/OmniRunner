# Milestone Celebration Runbook

> **Finding:** [L22-09] Progress celebration tímida
> **CI guard:** `npm run audit:milestone-celebration`
> **Source of truth:**
>
> - Domain: `omni_runner/lib/domain/value_objects/milestone_kind.dart`
>   (9 kinds × dedupKey + priority + distance threshold), `omni_runner/lib/domain/entities/milestone_entity.dart`,
>   `omni_runner/lib/domain/services/milestone_detector.dart` (pure
>   before/after diff detector), `omni_runner/lib/domain/services/milestone_copy_builder.dart`
>   (pt-BR / en / es copy).
> - Presentation reuses `omni_runner/lib/presentation/widgets/success_overlay.dart`
>   (confetti + animated checkmark already shipped).

## Why this runbook exists

L22-09 flagged that first-run / first-5K / first-week moments fired
no visual celebration. The confetti + checkmark widget already
existed (`ConfettiBurst` + `AnimatedCheckmark`) but nothing told the
app *when* to trigger them. The fix ships a pure domain pipeline
that detects new milestones from a `ProfileProgressEntity` delta and
hands the celebration presenter a typed [MilestoneEntity] with
locale-aware copy — no ad-hoc `if (distance > 5000)` scattered
across screens.

## Invariants (enforced by CI)

`npm run audit:milestone-celebration` fails closed if any of these
drift:

| # | Invariant                                                                                   | Why it matters                                                                                                                      |
| - | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 1 | `MilestoneKind` enum declares all 9 shipped kinds with unique non-empty `dedupKey`          | Dedup keys are persisted. Silently renaming one re-fires the milestone for every user whose old key is still in their local store.  |
| 2 | `MilestoneCopyBuilder` has a `case` branch per kind × per locale (pt-BR / en / es)          | A missing branch throws `no element` at runtime on the exact emotional moment the finding asked us to not get wrong.               |
| 3 | Detector file references `firstWeekSessionThreshold` constant                               | The 3-runs-per-week threshold is the narrative anchor from the finding; a silent bump to `5` breaks amateur persona calibration.   |
| 4 | This runbook exists and mutual-links `check-milestone-celebration` + the `L22-09` id        | Mutual linkage ensures future maintainers land on this page when the guard fails.                                                   |

## The 9 shipped kinds

| Priority | Kind                | dedupKey                     | Trigger                                                             |
| -------- | ------------------- | ---------------------------- | ------------------------------------------------------------------- |
| 1        | `firstRun`          | `first_run`                  | `lifetimeSessionCount` crosses 0 → ≥1                                |
| 2        | `firstFiveK`        | `first_5k`                   | Session ≥ 5000 m and previous lifetime max < 5000 m                  |
| 3        | `firstTenK`         | `first_10k`                  | Session ≥ 10000 m and previous max < 10000 m                         |
| 4        | `firstHalfMarathon` | `first_half_marathon`        | Session ≥ 21097.5 m and previous max < 21097.5 m                     |
| 5        | `firstMarathon`     | `first_marathon`             | Session ≥ 42195 m and previous max < 42195 m                         |
| 6        | `firstWeek`         | `first_week`                 | `weeklySessionCount` crosses `firstWeekSessionThreshold` (3) for the first time |
| 7        | `streakSeven`       | `streak_7`                   | `dailyStreakCount` crosses 7                                         |
| 8        | `streakThirty`      | `streak_30`                  | `dailyStreakCount` crosses 30                                        |
| 9        | `longestRunEver`    | `longest_run_ever:<decam>`   | Session distance strictly greater than previous lifetime max         |

`longestRunEver` is the only kind whose dedup key grows with the
trigger — the runtime-augmented key (`longest_run_ever:620` for a
6.2 km record) lets consecutive new records each fire once without
re-firing the same record.

## How to …

### Add a new milestone kind

1. Add the variant to `MilestoneKind` with a unique `dedupKey`, a
   priority **greater** than the largest existing priority, and
   either a `distanceThresholdM` or `null` (for streak / count
   kinds).
2. Add a detection branch inside `MilestoneDetector.detect`. Must
   gate on both the new-state condition **and** the prior-state not
   meeting it (otherwise the milestone re-fires every session).
3. Add a `case` branch to all three locale methods in
   `MilestoneCopyBuilder`.
4. Append a scenario to `milestone_detector_test.dart` and a
   coverage row to `milestone_copy_builder_test.dart`.
5. `npm run audit:milestone-celebration` — will fail until the CI
   guard's `REQUIRED_KINDS` list is extended to 10.

### Add a new locale

1. Append the locale to `AudioCoachLocale` (shared with the audio
   coach and challenge-invite subsystems).
2. Add a `_<locale>` method in `MilestoneCopyBuilder` with a
   `switch` over every `MilestoneKind`.
3. Update the guard's `REQUIRED_LOCALES` constant.
4. Add a scenario per kind in `milestone_copy_builder_test.dart`.

### Wire the celebration into a new post-session hook

1. Fetch `previousProgress` and `currentProgress` from the
   `ProgressionRepository`.
2. Fetch `alreadyCelebratedKeys` from local persistence
   (`SharedPreferences` under a `PrefsSafeKey.plain` entry so it
   survives reinstalls via account restoration).
3. Call `MilestoneDetector().detect(input)`.
4. For each returned milestone, in priority order, call
   `showSuccessOverlay(context, message: copy.title)` and persist
   `copy.dedupKey` into the set.
5. Emit a PostHog / analytics event `milestone_celebrated` with the
   `kind` + distance payload.

## Operational playbooks

### "Milestone fired twice for the same user"

Symptom: user reports they saw the "First 5K" confetti twice, or
analytics shows the same dedupKey twice for the same user within
24 h.

Diagnosis:

1. Read the user's local `alreadyCelebratedKeys` set from
   `SharedPreferences`. If `first_5k` is missing, persistence write
   failed after the overlay finished — possibly a hot-reboot mid-
   session.
2. Check the detector trace for both calls. If `previousMaxDistanceM`
   was reported as `0` for the second call, the pre-session snapshot
   fetch failed (network hiccup) and the session appeared to be the
   first-ever 5K a second time.

Fix: the dedup set is the only authoritative "already fired" source;
always write it from a single place **after** the overlay closes
(the `await showSuccessOverlay(...)` return is safe). If the snapshot
fetch fails, skip detection rather than assume zero — `null` previous
progress is OK only when `lifetimeSessionCount == 0`.

### "Milestone did not fire on an obvious first run"

Diagnosis:

1. Was `currentProgress.lifetimeSessionCount == 1`? If `0`, the
   session-credit step ran before the detector — confirm call order.
2. Is `alreadyCelebratedKeys` from a restored backup where
   `first_run` was already fired on an older install? Expected — we
   intentionally do NOT re-fire on account restore because the
   emotional beat was already used.

### "I want to retro-fire a milestone for existing users"

Almost always wrong. The design is "we celebrate the moment live,
not the memory". If a product decision insists, write a one-shot
migration that inserts the kind's dedup key into
`alreadyCelebratedKeys` for the affected users **and** surfaces a
banner ("Congratulations on your first 5K last month!") rather than
an overlay — the confetti overlay is reserved for live moments.

### "Copy is wrong in production"

The copy lives entirely in `MilestoneCopyBuilder`. Ship a hotfix
app release — do not attempt remote config overrides for this
surface; the copy carries emojis + Unicode that routinely choke
Firebase Remote Config and would turn the hero moment into mojibake.

## Detection signals

- CI guard (`npm run audit:milestone-celebration`) red in the
  `audit:check` pipeline.
- PostHog event `milestone_celebrated{kind}` with zero fires over a
  7-day window when `lifetimeSessionCount` p50 > 1 — indicates the
  wiring broke, not that no-one is running.
- Sentry warning `MilestoneDetector` tag — the detector is pure
  and should never throw; any exception here is a programming
  error.

## Rollback

The fix is pure additive (new domain classes, new tests, new CI
guard, new runbook). Reverting the fix commits removes the whole
pipeline without touching any existing surface.

## Cross-references

- [L22-06 Audio Cues Runbook](./AUDIO_CUES_RUNBOOK.md) — reuses
  `AudioCoachLocale` for sender-side i18n.
- [L22-08 Challenge Invite Viral Runbook](./CHALLENGE_INVITE_VIRAL_RUNBOOK.md) —
  milestones trigger the same share copy pipeline.
- `docs/audit/findings/L22-09-progress-celebration-timida.md`.
