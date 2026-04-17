---
id: L16-06
audit_ref: "16.6"
lens: 16
title: "Strava / TrainingPeaks OAuth sem telemetria de uso"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["webhook", "integration"]
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
# [L16-06] Strava / TrainingPeaks OAuth sem telemetria de uso
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `strava-webhook`, `trainingpeaks-sync` existem. Sem dashboard interno de: "% de atletas conectados ao Strava", "eventos/dia", "erros de sync".
## Risco / Impacto

— Feature flagship ruim → churn sem diagnóstico.

## Correção proposta

— Event `integration.strava.session_imported` + dashboard `/platform/integrations`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.6).