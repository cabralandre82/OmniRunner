---
id: L21-07
audit_ref: "21.7"
lens: 21
title: "Sem interoperabilidade com .fit real-time"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["webhook", "integration", "mobile", "personas", "athlete-pro"]
files:
  - omni_runner/lib/features/integrations_export/data/fit/fit_encoder.dart
correction_type: process
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
# [L21-07] Sem interoperabilidade com .fit real-time
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/features/integrations_export/data/fit/fit_encoder.dart` exporta .fit após sessão. Não importa .fit **em tempo real** do Garmin/Coros via ANT+ FIT File Transfer.
## Risco / Impacto

— Elite grava no Fenix, exporta manualmente → Omni Runner se torna só "depósito" sem valor agregado. Concorrência: Strava tem sync automático, TrainingPeaks tem auto-upload.

## Correção proposta

— OAuth com Garmin Connect (já lista "Health API" possível), Coros Stream, Polar AccessLink, Suunto. Cada conexão = webhook → `strava-webhook` pattern ([16.6]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.7).