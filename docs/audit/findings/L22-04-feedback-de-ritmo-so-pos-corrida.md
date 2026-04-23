---
id: L22-04
audit_ref: "22.4"
lens: 22
title: "Feedback de ritmo só pós-corrida"
severity: high
status: wont-fix
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
reopened_at: 2026-04-21
tags: ["mobile", "personas", "athlete-amateur", "strava-only-scope"]
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
note: |
  **Reclassificado `wont-fix` em 2026-04-21.** O finding pede
  guidance de ritmo **em tempo real** durante a corrida ("20s
  mais rápido que alvo. Desacelere."); o produto não faz mais
  tracking in-app desde Sprint 25.0.0 (`docs/ARCHITECTURE.md`
  §7 — Strava é fonte única), então não há loop de `pace`
  chegando tick-a-tick para o `PaceGuidanceVoiceTrigger`
  consumir. O código entregue no commit `6ef40ff` fica
  dormente na árvore (value object + trigger puro + 24
  testes); pickup é trivial caso tracking in-app volte.
  Follow-ups `L22-04-catalogue`/`L22-04-settings`/`L22-04-ui`
  ficam cancelados junto.
---
# [L22-04] Feedback de ritmo só pós-corrida
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🚫 wont-fix (Sprint 25.0.0 — Strava-only)
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
- `2026-04-21` — **Resolvido** (commit `6ef40ff`). Shipped pure-Dart `PaceGuidanceVoiceTrigger` que compara ritmo live vs banda alvo do `PlanWorkoutEntity` e emite `AudioEventType.paceAlert` com `state ∈ {too_fast, too_slow, on_target}`. Hysteresis (`confirmCount`), deadband (`deadbandSec`) e cooldown (`cooldownMs`, só para alertas — reforço `on_target` sempre passa) evitam TTS-flutter e nagging. 24 flutter_test cases + guard TS com 28 invariantes (`npm run audit:pace-guidance`) + runbook.
- `2026-04-21` — **Reclassificado `wont-fix`** após revisão de escopo. Finding assume tracking GPS in-app ("produto não fala durante"), mas o app não faz tracking próprio desde Sprint 25.0.0 (`docs/ARCHITECTURE.md` §7 — Strava-only). Não há loop tick-a-tick de `currentPaceSecPerKm` para alimentar `PaceGuidanceVoiceTrigger.evaluate()`. O commit fica dormente (puro-domain, zero platform, 24 testes ainda verdes contra VOs inertes); pickup-able se tracking in-app voltar. Follow-ups `L22-04-catalogue`/`L22-04-settings`/`L22-04-ui` ficam cancelados.