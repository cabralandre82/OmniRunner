---
id: L22-04
audit_ref: "22.4"
lens: 22
title: "Feedback de ritmo só pós-corrida"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "personas", "athlete-amateur"]
files:
  - omni_runner/lib/domain/usecases/pace_guidance_voice_trigger.dart
  - tools/audit/check-pace-guidance-voice.ts
  - docs/runbooks/PACE_GUIDANCE_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/usecases/pace_guidance_voice_trigger_test.dart
  - tools/audit/check-pace-guidance-voice.ts
linked_issues: []
linked_prs:
  - local:6ef40ff
owner: audit-bot
runbook: docs/runbooks/PACE_GUIDANCE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Pure-domain trigger shipped; AudioCueFormatter catalogue keys (pace.too_fast / pace.too_slow / pace.on_target) and SettingsRepository binding are tracked follow-ups (L22-04-catalogue, L22-04-settings)."
---
# [L22-04] Feedback de ritmo só pós-corrida
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Amador iniciante começa muito rápido ("burned out" em 5 min). Produto não fala durante.
## Correção proposta

— TTS em tempo real:

- "Você está 20 s mais rápido que alvo. Desacelere um pouco."
- "FC zona 3, ideal. Mantenha."
- A cada km: "1 km em 6:15, você está bem."

Customizável em `settings_screen.dart`: frequência, idioma, voz.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.4).
- `2026-04-21` — **Resolvido** (commit `6ef40ff`). Shipped pure-Dart `PaceGuidanceVoiceTrigger` que compara ritmo live vs banda alvo do `PlanWorkoutEntity` e emite `AudioEventType.paceAlert` com `state ∈ {too_fast, too_slow, on_target}`. Hysteresis (`confirmCount`), deadband (`deadbandSec`) e cooldown (`cooldownMs`, só para alertas — reforço `on_target` sempre passa) evitam TTS-flutter e nagging. 24 flutter_test cases + guard TS com 28 invariantes (`npm run audit:pace-guidance`) + runbook. Follow-ups: `L22-04-catalogue` (strings i18n no AudioCueFormatter), `L22-04-settings` (bind dos knobs no `SettingsRepository`).