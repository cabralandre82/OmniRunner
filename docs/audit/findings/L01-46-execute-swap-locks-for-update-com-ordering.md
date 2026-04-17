---
id: L01-46
audit_ref: "1.46"
lens: 1
title: "execute_swap — Locks FOR UPDATE com ordering"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["migration"]
files:
  - supabase/migrations/20260228150001
correction_type: migration
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
# [L01-46] execute_swap — Locks FOR UPDATE com ordering
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`supabase/migrations/20260228150001:420-432` faz lock em ordem de UUID para prevenir deadlock. Bom design.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.46]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.46).