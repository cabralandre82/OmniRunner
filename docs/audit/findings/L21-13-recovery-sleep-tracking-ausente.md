---
id: L21-13
audit_ref: "21.13"
lens: 21
title: "Recovery/sleep tracking ausente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "edge-function", "personas", "athlete-pro"]
files:
  - docs/product/RECOVERY_SLEEP_TRACKING.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product+mobile
runbook: docs/product/RECOVERY_SLEEP_TRACKING.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Spec ratificado em `docs/product/RECOVERY_SLEEP_TRACKING.md`.
  Decisão: ingestão read-only de Garmin/Polar/Apple Health/Health
  Connect, sem entrada manual em v1. Score derivado 'Omni Readiness'
  (0-100) com baseline 28-day pessoal. Consent LGPD Art. 11
  separado da auth do wearable; hard-delete on opt-out. Implementação
  Wave 4.
---
# [L21-13] Recovery/sleep tracking ausente
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `health` package (Apple Health, Google Fit) suporta sleep + HRV, mas repo não integra.
## Correção proposta

— `athlete_health_data` ganha `hrv_rmssd_ms`, `sleep_duration_h`, `readiness_score`. Edge function `evaluate-readiness` que sugere carga do dia.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.13).