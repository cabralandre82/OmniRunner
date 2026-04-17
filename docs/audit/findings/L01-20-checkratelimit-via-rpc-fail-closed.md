---
id: L01-20
audit_ref: "1.20"
lens: 1
title: "checkRateLimit via RPC — Fail-closed"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["rate-limit", "portal", "edge-function"]
files:
  - portal/src/lib/rate-limit.ts
  - supabase/functions/_shared/rate_limit.ts
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
# [L01-20] checkRateLimit via RPC — Fail-closed
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** Todos
## Achado
`supabase/functions/_shared/rate_limit.ts:29-58` retorna 503 `RATE_LIMIT_UNAVAILABLE` se a RPC falhar — **fail-closed**, correto. Contrasta com `portal/src/lib/rate-limit.ts:97-100` que faz fail-open para memory fallback — ver [1.21].
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.20).