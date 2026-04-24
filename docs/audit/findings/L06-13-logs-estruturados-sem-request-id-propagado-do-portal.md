---
id: L06-13
audit_ref: "6.13"
lens: 6
title: "Logs estruturados sem request_id propagado do portal"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: ["portal", "edge-function", "a11y", "ux"]
files:
  - portal/src/lib/logger.ts
  - portal/src/middleware.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 3af9c9b
  - 01674b0
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  portal/src/middleware.ts already generates / propagates
  x-request-id (L13-06) into both downstream request and response
  headers; portal/src/lib/logger.ts now lazily reads next/headers
  in activeRequestContext() so every log line auto-carries
  request_id without requiring callers to thread it explicitly.
  Edge Functions emit the same field via crypto.randomUUID() plus
  the forwarded x-request-id header, so a single search pivots
  across portal + Edge Functions for one user click.
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