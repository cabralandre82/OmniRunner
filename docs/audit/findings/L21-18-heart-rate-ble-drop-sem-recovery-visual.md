---
id: L21-18
audit_ref: "21.18"
lens: 21
title: "Heart-rate BLE drop sem recovery visual"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "personas", "athlete-pro"]
files: []
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L21-18] Heart-rate BLE drop sem recovery visual
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
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