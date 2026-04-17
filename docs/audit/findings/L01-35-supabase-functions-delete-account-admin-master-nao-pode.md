---
id: L01-35
audit_ref: "1.35"
lens: 1
title: "supabase/functions/delete-account — Admin master não pode se auto-deletar"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["edge-function", "performance"]
files:
  - supabase/functions/delete-account/index.ts
correction_type: process
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
# [L01-35] supabase/functions/delete-account — Admin master não pode se auto-deletar
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** admin_master
## Achado
`supabase/functions/delete-account/index.ts:44-48` bloqueia self-delete de `admin_master`. Good.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.35]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.35).