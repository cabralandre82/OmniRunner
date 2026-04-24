---
id: L21-18
audit_ref: "21.18"
lens: 21
title: "Heart-rate BLE drop sem recovery visual"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "personas", "athlete-pro"]
files:
  - docs/product/ATHLETE_PRO_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: mobile+platform
runbook: docs/product/ATHLETE_PRO_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_PRO_BASELINE.md`. Novo
  `DualHrSource` wrapper com fallback automático chest→optical
  após 5s sem amostra. UI mostra ícone-pílula 4-state (●●/●○/
  ○●/○○). `session_hr_samples.source` persiste qual sensor
  registrou cada amostra. Wave 4 fase D (mobile-only).
---
# [L21-18] Heart-rate BLE drop sem recovery visual
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `ble_reconnect_manager.dart` existe mas sem UI clara de "HRM caiu, reconectando". Elite treina com 2 HRM (chest + optical) — produto não duplica.
## Correção proposta

— Dual-source HR: priorizar chest BLE; fallback para optical se chest desconectar. UI mostra status.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.18]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.18).