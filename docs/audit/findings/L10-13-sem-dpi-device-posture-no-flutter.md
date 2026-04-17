---
id: L10-13
audit_ref: "10.13"
lens: 10
title: "Sem DPI (Device Posture) no Flutter"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "mobile"]
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
# [L10-13] Sem DPI (Device Posture) no Flutter
> **Lente:** 10 — CSO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— App não verifica: root/jailbreak, debugger attached, Frida hook, emulador em produção, integridade do APK.
## Correção proposta

— `flutter_jailbreak_detection` + Play Integrity API + bloqueio "soft" (warning) ou "hard" (bloquear transações financeiras em device comprometido).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.13).