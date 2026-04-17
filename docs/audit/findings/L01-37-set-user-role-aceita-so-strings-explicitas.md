---
id: L01-37
audit_ref: "1.37"
lens: 1
title: "set-user-role — Aceita só strings explícitas"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["idempotency", "ux"]
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
# [L01-37] set-user-role — Aceita só strings explícitas
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
Valida `role ∈ ['ATLETA', 'ASSESSORIA_STAFF']` e `onboarding_state ∈ ['NEW', 'ROLE_SELECTED']`. Idempotente.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.37]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.37).