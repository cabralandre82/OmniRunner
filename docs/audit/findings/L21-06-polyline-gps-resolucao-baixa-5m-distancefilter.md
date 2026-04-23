---
id: L21-06
audit_ref: "21.6"
lens: 21
title: "Polyline GPS resolução baixa (5m distanceFilter)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "performance", "personas", "athlete-pro", "gps"]
files:
  - omni_runner/lib/domain/entities/location_settings_entity.dart
  - omni_runner/lib/data/repositories_impl/location_stream_repo.dart
  - omni_runner/lib/core/storage/preferences_keys.dart
correction_type: code
test_required: true
tests:
  - omni_runner/test/domain/entities/location_settings_entity_test.dart
linked_issues: []
linked_prs:
  - local:9a4ec27
owner: mobile
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido em `9a4ec27` (fix). `LocationSettingsEntity` passa a
  expor um `RecordingMode` (standard | performance) e fábricas
  `.standard()` (5 m / high — preserva o default pré-L21-06 e a
  parity de bateria) e `.performance()` (1 m + `LocationAccuracy.
  bestForNavigation` — multi-constellation GNSS em iOS, fused
  provider de maior prioridade em Android). O enum
  `LocationAccuracy` ganhou a variante `bestForNavigation` e
  `LocationStreamRepo._mapAccuracy` passa a mapá-la para
  `geo.LocationAccuracy.bestForNavigation`. O catálogo
  `PreferencesKeys` (L11-05) ganhou a chave não-sensível
  `recording_mode` para a tela de configurações persistir a escolha
  do atleta. O modo é **opt-in** — default permanece 5 m / high —
  com trade-off documentado de ~+30 % de bateria e volume de
  pontos ~3-5×. Cobertura: 11 testes em
  `test/domain/entities/location_settings_entity_test.dart` que
  fixam os presets (5 m / high / standard vs. 1 m /
  bestForNavigation / performance), `copyWith`, contrato Equatable
  e cardinalidade dos enums, impedindo regressão silenciosa dos
  números citados neste finding.
---
# [L21-06] Polyline GPS resolução baixa (5m distanceFilter)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** mobile · domain + data
**Personas impactadas:** Athlete Pro (corredor de elite, análise biomecânica, replay de time-trial)
## Achado
— `location_settings_entity.dart:15` default `distanceFilterMeters = 5.0`. Em sprint (12 m/s), um ponto a cada 5 m = ponto a cada 0,4 s. Para análise biomecânica de elite é pobre.
## Correção proposta
— Modo "performance recording":

```dart
class LocationSettingsEntity {
  const LocationSettingsEntity({
    this.distanceFilterMeters = 5.0,
    this.accuracy = LocationAccuracy.high,
    this.mode = RecordingMode.standard,
  });

  // Elite mode: 1m filter, 1Hz sampling minimum, GNSS multi-constellation.
}
```

Trade-off: bateria (+30%) e storage. Opt-in.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.6).
- `2026-04-21` — Resolvido em `9a4ec27`. `LocationSettingsEntity` agora expõe um enum `RecordingMode` com fábricas `.standard()` (5 m / `LocationAccuracy.high`, default preservado) e `.performance()` (1 m / `LocationAccuracy.bestForNavigation` — GNSS multi-constelação em iOS). Adicionada a chave `PreferencesKeys.recordingMode` para o settings screen persistir a escolha do atleta (opt-in). Contrato fixado por 11 testes em `test/domain/entities/location_settings_entity_test.dart` que pinam presets, `copyWith`, Equatable e cardinalidade dos enums.
