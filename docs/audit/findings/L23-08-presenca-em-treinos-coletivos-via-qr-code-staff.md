---
id: L23-08
audit_ref: "23.8"
lens: 23
title: "Presença em treinos coletivos via QR code (staff_training_scan_screen.dart existe)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "migration", "personas", "coach"]
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
# [L23-08] Presença em treinos coletivos via QR code (staff_training_scan_screen.dart existe)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Tela de scan existe. Integração com `attendance` OK? Mas e **check-in geofenced** no local do encontro?
## Correção proposta

— Cada `coaching_event` (treino coletivo) tem `geofence`. App atleta auto-check-in quando entra no raio. Coach confirma via QR se necessário.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.8).