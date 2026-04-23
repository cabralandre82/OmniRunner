# Real-time pace guidance — L22-04 operational runbook

Finding: [L22-04](../audit/findings/L22-04-feedback-de-ritmo-so-pos-corrida.md)
Guard: `npm run audit:pace-guidance` · `tools/audit/check-pace-guidance-voice.ts`

## 1. Why this exists

Before L22-04, the audio coach spoke at three cadences: per-km announcements
(`VoiceTriggers`), per-interval time updates (`TimeVoiceTrigger`), and on
HR-zone changes (`HrZoneVoiceTrigger`). None of them spoke *between*
kilometers about pace.

The finding is explicit: "amador iniciante começa muito rápido ('burned
out' em 5 min). Produto não fala durante." The fix is a dedicated,
live-tick trigger that compares the athlete's current pace to the
workout's prescribed **target pace band** (`target_pace_min_sec_per_km`,
`target_pace_max_sec_per_km` on `PlanWorkoutEntity`) and emits a pace
alert in seconds — not in kilometers.

This runbook is the single source of truth for anyone wiring, tuning or
debugging the pace-guidance trigger.

## 2. Invariants (enforced by CI)

`npm run audit:pace-guidance` fails closed on drift in any of:

| Invariant | Enforced by |
|-----------|-------------|
| `PaceGuidanceState` declares `onTarget`, `tooFast`, `tooSlow`. | `enum PaceGuidanceState declared` |
| Wire strings stay `on_target` / `too_fast` / `too_slow` — consumers (formatter, TTS catalogue) switch on the raw string. | `wire string '<…>' present` |
| `PaceGuidanceVoiceTrigger.evaluate(...)` reads live pace and the prescribed target band. | `evaluate(...) reads *` |
| Hysteresis (`confirmCount`), cooldown (`cooldownMs`), and deadband (`deadbandSec`) are configurable — removing any one makes the trigger un-tunable. | `hysteresis / cooldown / deadband` |
| Emitted events are `AudioEventType.paceAlert`; payload carries `state`, `deviationSec`, echoed target band. | `emits AudioEventType.paceAlert`, `payload includes *` |
| Degenerate inputs (NaN, infinite, non-positive pace; null / inverted target band) are silenced, never spoken. | `NaN/infinite/non-positive pace guarded`, `inverted target band is silenced` |
| `reset()` exists. | `reset() method present` |
| File is pure Dart — no `dart:io` / `package:flutter/` imports. | `trigger is pure` |
| This runbook cross-links the guard and the finding. | `runbook cross-links *` |

Dart unit tests
(`flutter test test/domain/usecases/pace_guidance_voice_trigger_test.dart`,
24 cases) pin the observable behaviour: degenerate input handling,
hysteresis, cooldown, on_target reinforcement, priority ordering,
and state reset.

## 3. What shipped (mobile)

| File | Responsibility |
|------|----------------|
| `omni_runner/lib/domain/usecases/pace_guidance_voice_trigger.dart` | Pure-Dart stateful trigger. Emits at most one alert per confirmed state transition, with cooldown on same-type alerts. |
| `omni_runner/test/domain/usecases/pace_guidance_voice_trigger_test.dart` | 24 cases covering the contract. |

Deliberately **not** shipped in this finding:

- No `flutter_tts` wiring. `AudioCueFormatter` (L22-06) already knows how
  to format events by `payload['state']`; adding the catalogue keys
  `pace.too_fast`, `pace.too_slow`, `pace.on_target` for ptBR / en / es
  is a follow-up (`L22-04-catalogue`).
- No `settings_screen.dart` hook. The finding mentions a future
  "Customizável em settings_screen.dart: frequência, idioma, voz". The
  trigger parameters (`confirmCount`, `cooldownMs`, `deadbandSec`) are
  ready to be bound to `SettingsRepository` via a follow-up
  (`L22-04-settings`).

## 4. Decision logic (one page)

On every telemetry tick (typically 1 Hz):

```
evaluate(currentPaceSecPerKm, targetMin, targetMax, timestampMs):
    if currentPace is null / NaN / inf / ≤ 0 → null
    if target band is null / non-positive / inverted → null

    reading = classify(currentPace, targetMin, targetMax, deadband)
      # onTarget if pace ∈ [targetMin, targetMax]
      # tooFast if pace < targetMin − deadband
      # tooSlow if pace > targetMax + deadband

    # Hysteresis
    if reading == currentState → pending=0; null
    if reading == pendingState → pending += 1
    else                      → pendingState=reading; pending=1
    if pending < confirmCount → null

    # Confirmed state change
    currentState = reading; pending=0

    # Cooldown on alerts only (on_target reinforcement is always audible)
    if reading != onTarget and last alert was < cooldownMs ago → null

    emit { state, deviationSec, currentPaceSecPerKm, targetMin, targetMax }
```

### Priorities

| State | Priority (lower = more urgent) |
|-------|-------------------------------|
| `too_fast` / `too_slow` | **6** — mid-high. Above HR zone alerts (7), above distance announcements (10). |
| `on_target` | **11** — below HR zone alerts. Reinforcement; must never drown an HR or pace warning. |

## 5. How-to: wire the trigger into the live session

1. In the session screen / live coaching controller, construct the
   trigger once per session:

   ```dart
   final paceGuidance = PaceGuidanceVoiceTrigger(
     confirmCount: 3,     // ≈3 s of sustained drift
     cooldownMs: 30000,   // 30 s between same-type alerts
     deadbandSec: 5,      // 5 s/km slack around the band
   );
   ```

2. For every `WorkoutMetricsEntity` tick, call:

   ```dart
   final event = paceGuidance.evaluate(
     currentPaceSecPerKm: metrics.currentPaceSecPerKm,
     targetPaceMinSecPerKm: activeWorkout.targetPaceMinSecPerKm,
     targetPaceMaxSecPerKm: activeWorkout.targetPaceMaxSecPerKm,
     timestampMs: DateTime.now().millisecondsSinceEpoch,
   );
   if (event != null) audioCoachRepo.enqueue(event);
   ```

3. Call `paceGuidance.reset()` on `sessionStart` and `sessionResume`.

## 6. How-to: add a TTS string for the new event (L22-06 catalogue)

The trigger ships the event; the catalogue (L22-06) still needs entries
for ptBR / en / es. In `audio_cue_formatter.dart`:

```dart
// in _catalogue[Locale.ptBR]:
_paceTooFastKey: (payload) =>
    'Você está ${payload['deviationSec']} segundos mais rápido que o alvo. Desacelere um pouco.',
_paceTooSlowKey: (payload) =>
    'Você está ${payload['deviationSec']} segundos mais lento que o alvo. Acelere um pouco.',
_paceOnTargetKey: (_) => 'Você está no ritmo ideal. Mantenha.',
```

Resolve via `payload['state']`:

```dart
switch (event.payload['state']) {
  case 'too_fast': return _paceTooFastKey;
  case 'too_slow': return _paceTooSlowKey;
  case 'on_target': return _paceOnTargetKey;
}
```

Then add the catalogue keys to `AudioCueFormatter.translationKeys` so
the L22-06 guard keeps them locked.

## 7. How-to: tune `confirmCount` / `cooldownMs` / `deadbandSec`

| Symptom | Knob | Change |
|---------|------|--------|
| TTS fires on every GPS spike | `confirmCount` | ↑ (more consecutive ticks required) |
| Runner hears "desacelere" every 5 s | `cooldownMs` | ↑ |
| TTS fires when runner is 2 s off pace | `deadbandSec` | ↑ |
| Runner ignores silent coach during long sustained drift | `cooldownMs` | ↓ |

Defaults (confirmCount=3, cooldownMs=30000, deadbandSec=5) target a
5:00–6:00/km band with 1 Hz telemetry.

## 8. Operational playbooks

### "Runner complains coach never spoke about pace"

1. Check the active workout has `target_pace_min_sec_per_km` and
   `target_pace_max_sec_per_km` populated (`SELECT target_pace_min_sec_per_km,
   target_pace_max_sec_per_km FROM plan_workouts WHERE id = $1;`). If
   NULL, the trigger *intentionally* stays silent (free run).
2. Check the session screen is actually calling `paceGuidance.evaluate`
   on each tick (`grep -n paceGuidance live_coaching_controller`).
3. Check `AudioCoachRepo` has the `pace.*` catalogue keys wired for
   the runner's locale (otherwise the event is dropped silently by
   `AudioCueFormatter._fallback`).

### "Runner hears too many pace alerts"

1. Raise `cooldownMs` via `SettingsRepository` (or hard-code a new
   default if the complaint is systemic).
2. Raise `deadbandSec` if the complaint is about borderline alerts.

### "Runner says the coach keeps saying they are too fast even when on pace"

1. Check `confirmCount ≥ 2` (otherwise a single GPS glitch will confirm
   a false state).
2. Verify the workout's target band is the *intended* band (coach may
   have prescribed a tighter band than the runner can sustain — a
   coaching issue, not a trigger bug).

## 9. Detection signals

- `audio_events` telemetry (when wired): count of `paceAlert` events
  per session. Sessions with `pace_alert_count > 20` for a 5 km run
  likely need cooldown/deadband tuning.
- User feedback: "coach nagged" or "coach silent" on workout feedback.

## 10. Rollback

If the trigger causes a regression:

1. Stop calling `paceGuidance.evaluate(...)` from the live coaching
   controller (one-line change) — the rest of the voice coach continues
   to work.
2. Leave the trigger class in place; re-enable after fixing the bug.
3. Do **not** delete the `AudioEventType.paceAlert` enum value — other
   consumers (future alerts: HR drift, cadence) may reuse it.

## 11. Cross-references

- [L22-04 finding](../audit/findings/L22-04-feedback-de-ritmo-so-pos-corrida.md)
- [L22-06 voice coaching runbook](./AUDIO_CUES_RUNBOOK.md) — the
  catalogue + TTS wiring layer that turns these events into speech.
- [L23-13 athlete feedback gate](./ATHLETE_FEEDBACK_GATE_RUNBOOK.md) —
  the post-run feedback side of the same coaching loop.
- [WorkoutMetricsEntity]
  (`omni_runner/lib/domain/entities/workout_metrics_entity.dart`)
- [PlanWorkoutEntity]
  (`omni_runner/lib/domain/entities/plan_workout_entity.dart`)
