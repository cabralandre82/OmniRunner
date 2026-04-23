---
id: L21-07
audit_ref: "21.7"
lens: 21
title: "Sem interoperabilidade com .fit real-time"
severity: high
status: wont-fix
wave: 1
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["webhook", "integration", "mobile", "personas", "athlete-pro", "strava-only-scope"]
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
note: |
  **wont-fix (2026-04-21).** O finding pede OAuth direto com
  Garmin/Coros/Polar/Suunto para receber `.fit` em tempo
  real e tratar cada um como webhook-push paralelo ao
  `strava-webhook`. A decisão de produto da Sprint 25.0.0
  (`docs/ARCHITECTURE.md` §7) definiu **Strava como fonte
  única** de atividades — qualquer dispositivo que
  sincroniza com Strava (Garmin, Coros, Polar, Apple Watch,
  Fitbit) chega ao Omni Runner via o mesmo pipeline. Ter
  N integrações diretas quebra a invariante "uma única
  fila de atividades" que todo o anti-cheat / XP /
  badge / missão assume. Se no futuro quisermos sair da
  dependência de Strava, este finding vira o blueprint da
  alternativa; até lá, permanece `wont-fix` por decisão
  de arquitetura, não por falta de solução técnica.
---
# [L21-07] Sem interoperabilidade com .fit real-time
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🚫 wont-fix (Sprint 25.0.0 — Strava-only)
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
- `2026-04-21` — **Fechado como `wont-fix`**. Strava é fonte única de atividades desde Sprint 25.0.0 (`docs/ARCHITECTURE.md` §7). Dispositivos Garmin/Coros/Polar chegam ao Omni via sync-to-Strava → webhook Omni existente; não vamos abrir N canais paralelos.