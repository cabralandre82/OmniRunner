---
id: L11-05
audit_ref: "11.5"
lens: 11
title: "flutter_secure_storage: ^10.0.0 mas release inclui shared_preferences"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile"]
files: []
correction_type: test
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
# [L11-05] flutter_secure_storage: ^10.0.0 mas release inclui shared_preferences
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `pubspec.yaml:63,55` declara `flutter_secure_storage: ^10.0.0` e `shared_preferences: ^2.5.4`. Auditoria anterior em [1.1] já identifica uso. Risco: devs confundem qual storage usar para dados sensíveis.
## Correção proposta

— Lint rule custom proibindo `shared_preferences` para chaves contendo `token|key|secret|auth` via `custom_lint` package.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.5).