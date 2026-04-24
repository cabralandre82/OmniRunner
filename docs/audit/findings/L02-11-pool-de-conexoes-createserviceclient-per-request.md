---
id: L02-11
audit_ref: "2.11"
lens: 2
title: "Pool de conexões createServiceClient per-request"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["atomicity", "portal", "edge-function", "pool", "fixed"]
files:
  - portal/src/lib/supabase/service.ts
  - tools/audit/check-k4-security-fixes.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 99ac6c7
  - 4d7950b
  - d63d253
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — `createServiceClient` is now module-cached with a
  configKey derived from the env tuple (URL + key length, never
  the secret value). A warm lambda reuses the same Supabase
  client (and therefore the same keep-alive HTTP socket pool to
  PostgREST) across requests. Cold starts pay one construction
  cost. Tests can call `__resetServiceClientForTests` to drop
  the singleton between mocks. Eliminates ECONNRESET against
  PostgREST under load and saves the 5-15 ms TLS handshake per
  call.
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