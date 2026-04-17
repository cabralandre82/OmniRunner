---
id: L19-09
audit_ref: "19.9"
lens: 19
title: "Connection pooling não documentado"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["atomicity", "portal", "edge-function"]
files: []
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
# [L19-09] Connection pooling não documentado
> **Lente:** 19 — DBA · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Supabase oferece PgBouncer transacional/session. Portal usa `@supabase/ssr` (ephemeral); Edge Functions criam client por request. Em burst alto, conexões saturam.
## Correção proposta

— Documentar: Portal usa pool **transaction mode**; Edge Functions também. Configurar `poolSize` no client.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.9).