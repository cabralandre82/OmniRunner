---
id: L22-06
audit_ref: "22.6"
lens: 22
title: "Voice coaching parcial"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "reliability", "personas", "athlete-amateur", "i18n", "audio"]
files:
  - omni_runner/lib/domain/value_objects/audio_coach_locale.dart
  - omni_runner/lib/domain/services/audio_cue_formatter.dart
  - omni_runner/lib/domain/usecases/countdown_voice_trigger.dart
  - omni_runner/lib/domain/usecases/motivation_voice_trigger.dart
  - omni_runner/lib/domain/usecases/hydration_voice_trigger.dart
  - omni_runner/lib/data/datasources/audio_coach_service.dart
  - omni_runner/lib/data/repositories_impl/audio_coach_repo.dart
  - tools/audit/check-voice-coaching-i18n.ts
  - docs/runbooks/AUDIO_CUES_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/services/audio_cue_formatter_test.dart
  - omni_runner/test/domain/usecases/countdown_voice_trigger_test.dart
  - omni_runner/test/domain/usecases/motivation_voice_trigger_test.dart
  - omni_runner/test/domain/usecases/hydration_voice_trigger_test.dart
  - tools/audit/check-voice-coaching-i18n.ts
linked_issues: []
linked_prs:
  - local:9dab4ec
owner: mobile
runbook: docs/runbooks/AUDIO_CUES_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Shipped the three cues the finding called out explicitly plus
  multi-locale support, in 5 defense layers:

  1. `AudioCoachLocale` (value object) — enum `ptBR`/`en`/`es`
     carrying BCP-47 tags (`pt-BR`/`en-US`/`es-ES`) + `fromTag`
     null-safe resolver that falls back to `ptBR` on unknown
     input so voice coaching never crashes the session.
  2. `AudioCueFormatter` (domain service) — single locale-aware
     text renderer. 15 translation keys × 3 locales + 3
     motivational pools + 1 hydration reminder per locale. The
     `translationKeys` Set is a declared invariant the CI guard
     matches against the catalogue.
  3. Three new voice triggers (domain usecases):
     - `CountdownVoiceTrigger` — priority 2 (interrupts), fires
       once per whole second from `countdownSec` down to 0 (GO!),
       stateful, `reset()` per session.
     - `MotivationVoiceTrigger` — priority 14, fires every
       `intervalMs` (default 10 min) of moving time, rotates
       modulo the locale's pool, `isPaused` suppression,
       `minSpacingMs` cool-down floor.
     - `HydrationVoiceTrigger` — priority 13, silent during
       `warmupMs` (default 20 min), then every `intervalMs`
       after with the locale's hydration phrase.
  4. `AudioCoachService.init({locale: ...})` + new `setLocale()`
     mid-session; `AudioCoachRepo` delegates text rendering to
     the formatter and exposes `setLocale(...)` which updates
     both formatter and engine. Defaults preserve 100% backward
     compat (existing callers still speak pt-BR unchanged).
  5. CI guard (`npm run audit:voice-coaching-i18n`) asserts
     enum shape, BCP-47 tags, `fromTag` factory, catalogue
     coverage per locale, motivational pool non-empty per
     locale, 3 trigger files with the expected class contract,
     and runbook cross-linkage. Smoke-tested: removing an `es`
     catalogue entry surfaces `missing: countdown.go` on the
     `es` block.

  Tests: 71 new Dart cases (31 formatter + 11 countdown +
  9 motivation + 9 hydration + 11 `fromTag` cases embedded
  in formatter suite). `flutter analyze` clean, full suite
  2199/2199 green (was 2128; +71).

  Runbook `AUDIO_CUES_RUNBOOK.md` (8 sections) covers invariants
  table, "how to add a new locale / cue type", mid-session
  locale swap code snippet, 6 operational playbooks including
  priority contract for "coach talks over itself".

  Code: `9dab4ec`.
---
# [L22-06] Voice coaching parcial
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** mobile
**Personas impactadas:** atleta amador, atleta pro
## Achado
— `flutter_tts` nos deps. Uso real: talvez só "pace alert". Faltam:

- Countdown "3, 2, 1, GO"
- Motivação periódica ("Você está indo bem!")
- Avisos de hidratação em corrida longa
## Correção proposta

— `AudioCoachService` configurável. Multi-idioma (pt-BR, en, es).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.6).
- `2026-04-21` — ✅ Fixado. `AudioCoachLocale` (ptBR/en/es), `AudioCueFormatter` com 15 chaves × 3 locales, 3 novos triggers (countdown/motivation/hydration), `AudioCoachService.setLocale` mid-session, CI `audit:voice-coaching-i18n` (20 invariants), runbook `AUDIO_CUES_RUNBOOK.md`. 71 novos testes Dart, flutter analyze clean, 2199/2199 green. Commit `9dab4ec`.
