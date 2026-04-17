---
id: L02-11
audit_ref: "2.11"
lens: 2
title: "Pool de conexões createServiceClient per-request"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["atomicity", "portal", "edge-function"]
files:
  - portal/src/lib/supabase/service.ts
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
# [L02-11] Pool de conexões createServiceClient per-request
> **Lente:** 2 — CTO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
`portal/src/lib/supabase/service.ts:10` cria um novo client a cada `createServiceClient()`. Em Vercel Serverless, cold start abre nova connection para PostgREST. Hot invocations reutilizam instance via Node module cache — mas cada request chama `createServiceClient()` nova, criando nova instância. PostgREST REST não mantém pool de DB connections no client-side (é stateless HTTP), então múltiplos clients não saturam connections — **mas** o Supabase Pool (PgBouncer) tem limite de conexões. Em picos com muitas Edge Functions + Portal simultâneos, pode haver starvation.
## Correção proposta

Confirmar que Supabase Pool está em transaction-mode (default). Reduzir statement_timeout do service role para 15s para evitar queries longas segurando connection.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.11).