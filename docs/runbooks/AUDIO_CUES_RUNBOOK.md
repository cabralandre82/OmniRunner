# Audio coaching — L22-06 operational runbook

Finding: [L22-06](../audit/findings/L22-06-voice-coaching-parcial.md)
Guard: `npm run audit:voice-coaching-i18n` · `tools/audit/check-voice-coaching-i18n.ts`

## 1. Why this exists

Before L22-06 the audio coach existed on paper — `flutter_tts` was on the
dependency list and `AudioCoachService` spoke Portuguese — but three of the
four **explicitly-mentioned features in the finding** were missing: the
"3, 2, 1, GO" pre-start countdown had no trigger, there was no periodic
motivational cue, and there was no hydration reminder for long runs. On top
of that, the whole stack was hardcoded to pt-BR: the service's `init()`
default, every static string in `AudioCoachRepo._buildText`, and every
event built by the metric triggers. Even if the TTS engine could speak
`en-US`, the phrases handed to it would still be Portuguese.

This runbook is the single source of truth for anyone adding a new cue
type, a new locale, or diagnosing why the coach went silent on a real
session.

## 2. Invariants (enforced by CI)

`npm run audit:voice-coaching-i18n` fails closed on drift in any of:

| Invariant | Enforced by |
|-----------|-------------|
| `AudioCoachLocale` declares `ptBR` / `en` / `es` with the exact BCP-47 tags (`pt-BR`, `en-US`, `es-ES`). | `checkLocaleEnum()` |
| `AudioCoachLocale.fromTag(...)` factory is present (null-safe resolver). | `checkLocaleEnum()` |
| `AudioCueFormatter.translationKeys` is a declared `Set<String>` and every key has a corresponding `static const _<key>Key` symbol. | `checkFormatter()` |
| Every locale block (`ptBR` / `en` / `es`) in `_catalogue` contains an entry for every declared key. No gaps. | `checkFormatter()` |
| Every locale has a non-empty `motivationalPhrases` pool. | `checkFormatter()` |
| `countdown_voice_trigger.dart`, `motivation_voice_trigger.dart`, and `hydration_voice_trigger.dart` all ship a `class <Name>VoiceTrigger` with a `AudioEventEntity? evaluate(...)` method. | `checkTriggers()` |
| This runbook exists and cross-references the guard (`audit:voice-coaching-i18n`) and the finding (`L22-06`). | `checkRunbook()` |

Dart unit tests (`flutter test test/domain/services/audio_cue_formatter_test.dart`
and the three `*_voice_trigger_test.dart` files) pin the observable
behaviour: 60 cases covering catalogue coverage, locale fallback,
countdown ordering, motivation rotation + cool-down, hydration warmup,
and isPaused suppression.

## 3. What shipped (mobile)

| File | Responsibility |
|------|----------------|
| `omni_runner/lib/domain/value_objects/audio_coach_locale.dart` | `AudioCoachLocale` enum (`ptBR`/`en`/`es`) + `fromTag` resolver. |
| `omni_runner/lib/domain/services/audio_cue_formatter.dart` | Pure, locale-aware formatter. Per-locale catalogues + motivational pools + hydration reminder. |
| `omni_runner/lib/domain/usecases/countdown_voice_trigger.dart` | Emits `countdown` events {5,4,3,2,1,0}. Priority 2 (interrupts). |
| `omni_runner/lib/domain/usecases/motivation_voice_trigger.dart` | Emits a motivational phrase every N minutes of moving time, rotating through the pool. Priority 14. |
| `omni_runner/lib/domain/usecases/hydration_voice_trigger.dart` | Emits a hydration reminder after a warmup window, repeating every N minutes. Priority 13. |
| `omni_runner/lib/data/datasources/audio_coach_service.dart` | `init(locale: …)` + `setLocale(...)` mid-session. |
| `omni_runner/lib/data/repositories_impl/audio_coach_repo.dart` | Delegates text rendering to `AudioCueFormatter`. `setLocale` swaps both formatter and engine. |

## 4. How to …

### 4.1 Add a new locale

1. Add the variant to `AudioCoachLocale` with its BCP-47 tag
   (`fr('fr-FR')`).
2. Extend `AudioCoachLocale.fromTag` to recognise `fr*`.
3. Add a block in `_catalogue` covering every key from
   `AudioCueFormatter.translationKeys`. The CI guard fails if one is
   missing.
4. Add a non-empty pool entry in `_motivationalPhrases`.
5. Extend `audio_cue_formatter_test.dart`: add a locale-specific
   group mirroring the `en` / `es` ones (distance+pace, countdown 0,
   hydration phrase, motivational pool first entry).
6. Run `flutter test` and `npm run audit:voice-coaching-i18n`. Both
   must be green in the same commit.

### 4.2 Add a new cue type

1. Append a value to `AudioEventType`.
2. Add a static const key + a locale-specific entry per locale in
   `_catalogue`. Add the key to `translationKeys`.
3. Extend `AudioCueFormatter.format`'s switch with the new event.
4. Ship the trigger that emits the event as a new use-case in
   `omni_runner/lib/domain/usecases/`. Follow the pattern of
   `MotivationVoiceTrigger` (stateful, `reset()` for new session,
   `evaluate(...)` returns `AudioEventEntity?`).
5. Write a `<name>_voice_trigger_test.dart` covering: initial
   silence, first emission boundary, double-fire suppression, rotation
   (if any), `isPaused` suppression, `reset` behaviour, custom-config
   variant, per-locale variant.
6. Run both the formatter tests (coverage invariant) and the new
   trigger tests.

### 4.3 Swap the active locale mid-session

Production callers hold `AudioCoachRepo` (the concrete class) via
`GetIt` / `IAudioCoach`. To swap:

```dart
final repo = sl<IAudioCoach>() as AudioCoachRepo;
await repo.setLocale(AudioCoachLocale.en);
```

This:

1. Replaces the internal `AudioCueFormatter` — all future events
   render in the new locale.
2. Calls `_service.setLocale(locale)` which in turn calls
   `flutter_tts.setLanguage(tag)`. If the engine rejects the tag
   (rare but possible on low-resource devices), the failure is
   logged through `AppLogger.warn` and the coach continues speaking
   in the old voice — **never silent**, per the "voice coaching
   must never crash the session" mandate.

## 5. Playbooks

### 5.1 CI guard failed

Root-cause by line marker in the guard output:

- `locale: <variant> declared with tag …` — someone added/renamed
  a locale without updating both the enum entry and its BCP-47 tag.
  Align with §4.1.
- `formatter: <locale> catalogue covers all keys` — a new
  translation key was added in `_catalogue[ptBR]` but not propagated
  to the other locales. Translate + add.
- `formatter: <locale> motivational pool non-empty` — someone
  trimmed the pool to zero. At least one phrase per locale.
- `trigger: <file>` — a trigger file was moved or renamed. Either
  update `REQUIRED_TRIGGERS` in the guard (with review justification)
  or restore the file's path.
- `runbook: cross-links the audit:voice-coaching-i18n guard` — this
  runbook lost its reference to the guard. Re-add the exact string
  `audit:voice-coaching-i18n`.

### 5.2 User reports "no countdown before my run starts"

1. Verify the session-start UI wires `CountdownVoiceTrigger` and
   calls `evaluate(elapsedMs)` every tick.
2. Verify `AudioCoachRepo` has been `init()`-ed (no TTS means no
   cues — check for `AppLogger.error` tagged `AudioCoach` at session
   boot).
3. Verify device volume and media ducking. iOS requires
   `setSharedInstance(true)` (already done in `AudioCoachService`);
   Android varies by OEM (some disable TTS when DND is on).

### 5.3 User reports "I set Spanish in settings but I still hear pt-BR"

1. The UI toggle should call `repo.setLocale(AudioCoachLocale.es)`.
   Confirm via runtime breakpoint.
2. Check `flutter_tts.getLanguages` on the target device; some
   devices lack the Spanish voice pack. The coach will still call
   `setLanguage('es-ES')` but the engine may fall back to the
   default — phrases will still be in Spanish text but pronunciation
   will match the engine's fallback voice.

### 5.4 "Hydration reminder fires at minute 1 on a 3-minute run"

Expected behaviour: `HydrationVoiceTrigger` is silent until
`warmupMs` (default 20 min) of **moving** time has elapsed. If a
user reports premature firing, it usually means custom config
passed a shorter `warmupMs` — inspect the caller.

### 5.5 Adding a new motivational phrase

1. Append to every locale's list in `_motivationalPhrases`. Keeping
   lists length-balanced is **not** required — rotation is modulo
   the length of the active locale's list.
2. Extend the formatter test's `motivationalPhrases` case that checks
   the first entry for a keyword, if the first phrase changed.

### 5.6 "The coach keeps talking over itself"

Priority contract (lower = more urgent, wins conflict):

| Priority | Event kind |
|----------|-----------|
| 2 | `countdown` (pre-start) |
| 5–7 | `heartRateAlert` (zone change, hysteresis) |
| 8 | ghost pass (custom with text) |
| 10 | `distanceAnnouncement` |
| 12 | `timeAnnouncement` |
| 13 | hydration reminder (custom with action `HYDRATION`) |
| 14 | motivational (custom with action `MOTIVATION`) |

`AudioCoachRepo` rules:

- `priority <= interruptThreshold (5)`: stop current, speak now.
- `priority <= queueThreshold (15)`: enqueue (max 5 items).
- `priority > 15`: discard if queue non-empty.

If a user reports overlap, inspect whether a new trigger was added
with an overly-urgent priority. Don't weaken the countdown's
interrupt semantics — a runner waiting on "3, 2, 1, GO" must hear
it immediately.

## 6. Detection signals

- CI guard failure (`npm run audit:voice-coaching-i18n`).
- Dart unit tests failing on catalogue coverage
  (`audio_cue_formatter_test.dart` "all locales cover every
  translation key").
- User feedback: "audio keeps crashing" (boot-time TTS init error
  logged via `AppLogger.error` tagged `AudioCoach`).
- Sentry: exceptions from `flutter_tts.setLanguage` / `speak`
  (caught and logged as warnings — shouldn't surface as fatals).

## 7. Rollback

The change is additive (new files + `AudioCueFormatter` delegation).
To roll back to the monolingual pt-BR behaviour:

1. Revert the two mobile commits that touched
   `audio_coach_repo.dart`, `audio_coach_service.dart`, and the new
   domain/value_objects + domain/services modules.
2. Delete the 3 new trigger files.
3. Re-run `flutter analyze` + `flutter test` — existing voice_triggers
   / hr_zone_voice_trigger / time_voice_trigger / ghost_voice_trigger
   tests continue to pass because their contract was preserved.

## 8. Cross-references

- **L22-05** — Groups nearby: amateurs may also hit hydration
  reminders during long "discovery runs"; these runbooks share
  the L22 amateur persona.
- **L21-06** — Performance GPS mode: performance-mode sessions
  generate denser cues (distance boundaries fire faster). The
  priority/queue rules here keep the stream coherent.
- **L11-05** — Secure storage: the locale preference (UI toggle) is
  non-sensitive and may live in `SharedPreferences` via
  `PreferencesKeys`. Never store a voice API token there.
- **L17-05** — Logger contract: `AudioCoachService` emits warnings
  through `AppLogger`, which routes to Sentry per the non-Error
  handling fix.
