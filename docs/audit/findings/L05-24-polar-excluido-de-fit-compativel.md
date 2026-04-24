---
id: L05-24
audit_ref: "5.24"
lens: 5
title: "Flutter: Polar (e correção Suunto) excluídos de _fitCompatible"
severity: high
status: fixed
wave: 0
discovered_at: 2026-04-24
fixed_at: 2026-04-24
closed_at: 2026-04-24
tags: ["workout", "flutter", "watch", "integration", "coach", "athlete"]
files:
  - omni_runner/lib/presentation/screens/athlete_workout_day_screen.dart
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: ["34aa89b"]
owner: platform-workout
runbook: null
effort_points: 1
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-24] Flutter: Polar (e correção Suunto) excluídos de _fitCompatible

> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 0 · **Status:** fix-pending

**Camada:** App Flutter
**Personas impactadas:** atleta com Polar (botão "enviar para relógio" nunca aparece), coach (base de atletas Polar fica refém do próprio workflow)

## Achado

O gate do botão "Enviar para relógio" em `athlete_workout_day_screen.dart:49` usa um set hard-coded que inclui apenas Garmin, Coros e Suunto:

```49:49:omni_runner/lib/presentation/screens/athlete_workout_day_screen.dart
  static const _fitProviders = {'garmin', 'coros', 'suunto'};
```

Esse set é comparado contra DUAS fontes:

1. `coaching_members.watch_type` (override manual do coach) — enum permite `{garmin, coros, suunto, apple_watch, polar, other}` (migration `20260315000000_member_watch_type.sql:13`).
2. `coaching_device_links.provider` (via Strava/TrainingPeaks/linkagem direta) — permite `{garmin, apple, polar, suunto, strava, training_peaks}`.

Como `polar` não está em `_fitProviders`, o botão nunca aparece para:
- Atletas que o coach marcou `watch_type = 'polar'` manualmente.
- Atletas que linkaram um relógio Polar via `coaching_device_links`.

O `.FIT` é **o formato nativo de import** dos relógios Polar (Vantage, Pacer, Grit, Ignite via Polar Flow). Excluir Polar não é uma decisão arquitetural — é um bug de omissão.

## Impacto

- Atletas Polar nunca recebem o treino estruturado no relógio → rodam "em branco" sem pace targets nem laps automáticos.
- Coaches com base heterogênea (Garmin + Polar) fazem dupla jornada: enviam `.fit` a Garmin pelo app, mas precisam exportar manualmente e compartilhar com os atletas Polar por WhatsApp.
- Palavra na comunidade: "Omni não suporta Polar" (errado — a parte cara, o encoder, já funciona; só o gate está errado).

Polar é a **3ª marca mais vendida** no segmento de corrida amadora brasileiro (depois de Garmin e Apple Watch), com share crescente entre atletas < 30 anos que evitam o ecossistema Garmin pelo preço. Excluí-los é um tiro no pé comercial.

## Correção proposta

Adicionar `'polar'` ao set (e adicionar `'apple'` como provider de device_link mapeado para `apple_watch` no watch_type, embora Apple Watch NÃO seja fit-compatível — cobrado em L22-10):

```dart
static const _fitProviders = {'garmin', 'coros', 'suunto', 'polar'};
```

Apple Watch fica fora deste set deliberadamente — não aceita `.fit` (exige WorkoutKit, coberto pela L22-10 wave 4).

## Teste de regressão

- Manual: atleta com `watch_type='polar'` ou `device_link.provider='polar'` vê o botão "Enviar para relógio".
- Manual: atleta com `watch_type='apple_watch'` continua SEM ver o botão (Apple usa WorkoutKit, não .fit).

Flutter widget test fica como TODO menor porque exige mock extenso de SupabaseClient; validação por smoke manual é aceitável nesta classe de mudança (adicionar string num set).

## Cross-refs

- L22-10 (fixed-docs) — Apple Watch / Wear OS nativo, Wave 4.
- L05-25 (sibling) — Portal export .fit direto (outro gap de passagem de treino).

## Histórico

- `2026-04-24` — Descoberto durante vistoria de passagem de treino.
- `2026-04-24` — Fixed: `polar` adicionado ao `_fitProviders`.
