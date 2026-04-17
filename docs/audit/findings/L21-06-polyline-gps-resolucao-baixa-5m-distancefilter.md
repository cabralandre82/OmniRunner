---
id: L21-06
audit_ref: "21.6"
lens: 21
title: "Polyline GPS resolução baixa (5m distanceFilter)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "performance", "personas", "athlete-pro"]
files: []
correction_type: code
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L21-06] Polyline GPS resolução baixa (5m distanceFilter)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
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