---
id: L11-08
audit_ref: "11.8"
lens: 11
title: "Flutter sdk: '>=3.8.0 <4.0.0' — permite 3.9, 3.10…"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile"]
files: []
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
# [L11-08] Flutter sdk: '>=3.8.0 <4.0.0' — permite 3.9, 3.10…
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Dart SDK breaking em minor não é impossível (null safety histórico). CI usa `flutter-version: '3.41.x'` — hardcoded, OK.
## Correção proposta

— Atualizar pubspec para `sdk: '>=3.8.0 <3.13.0'` e alinhar no CI.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.8).