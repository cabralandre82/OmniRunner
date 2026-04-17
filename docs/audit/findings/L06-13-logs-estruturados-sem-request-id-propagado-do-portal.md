---
id: L06-13
audit_ref: "6.13"
lens: 6
title: "Logs estruturados sem request_id propagado do portal"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal", "edge-function", "a11y", "ux"]
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
# [L06-13] Logs estruturados sem request_id propagado do portal
> **Lente:** 6 — COO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Edge Functions geram `requestId = crypto.randomUUID()`. Portal Next.js `logger` não recebe/gera `x-request-id`. Correlação cross-serviço impossível.
## Correção proposta

— Middleware do Next injetar `x-request-id` se não vier do cliente, propagar em toda chamada `fetch(supabase, ...)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.13).