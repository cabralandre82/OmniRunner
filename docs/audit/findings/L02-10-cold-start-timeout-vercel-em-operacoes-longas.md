---
id: L02-10
audit_ref: "2.10"
lens: 2
title: "Cold start + timeout Vercel em operações longas"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-20
tags: ["finance", "mobile", "portal", "edge-function", "cron"]
files:
  - portal/src/lib/supabase/service.ts
  - portal/src/lib/clearing.ts
  - portal/src/app/api/cron/settle-clearing-batch/route.ts
  - portal/src/lib/route-policy.ts
  - portal/src/lib/api/csrf.ts
  - supabase/migrations/20260420100000_l02_clearing_settle_chunked.sql
correction_type: process
test_required: true
tests:
  - tools/test_l02_10_clearing_settle_chunked.ts
  - portal/src/lib/clearing.test.ts
  - portal/src/app/api/cron/settle-clearing-batch/route.test.ts
linked_issues: []
linked_prs: ["88deb25"]
owner: platform
runbook: docs/runbooks/CRON_HEALTH_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Solução em 4 camadas: (1) `fn_settle_clearing_chunk(window_start,
  window_end, limit, debtor_group_id)` em PL/pgSQL processa até `limit`
  (default 50, máx 500) settlements pendentes usando
  `FOR UPDATE SKIP LOCKED` + `EXCEPTION` por linha — single-row failure
  não aborta o chunk; (2) `fn_settle_clearing_batch_safe(limit,
  window_hours)` é o cron-safe wrapper que reusa `cron_run_state` +
  `pg_try_advisory_xact_lock` (L12-03) para overlap protection e grava
  metadados em `last_meta`; (3) `pg_cron` agenda `settle-clearing-batch`
  a cada minuto in-DB (`* * * * *`), eliminando dependência do runtime
  serverless para o caminho primário; (4) `POST /api/cron/settle-clearing-batch`
  fica como surface de replay manual com `CRON_SECRET` (constant-time
  compare), `maxDuration=60`, soft-time-budget de 50s, e drain loop
  bounded por `max_chunks` + `remaining=0` + `processed=0`. Verificação:
  9/9 integration tests verdes (chunk size, debtor scoping, insufficient
  vs failed, validação de input, cron-state lifecycle), 40/40 vitest
  (lib helper + route handler), `audit verify` 348/348. Backlog drena
  em ≤ N+1 minutos para qualquer N atual de pendings.
---
# [L02-10] Cold start + timeout Vercel em operações longas
> **Lente:** 2 — CTO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Platform admin (relatórios/exports), Coach (batch)
## Achado
`createServiceClient` em `portal/src/lib/supabase/service.ts:7-9` tem timeout de 15s. Operações de batch (`settleWindowForDebtor` em `clearing.ts:296-329`) fazem loop síncrono de `settle_clearing` por settlement pending — para 500 settlements pendentes em uma janela, isso pode exceder 60s mesmo em Vercel Pro.
## Risco / Impacto

Deploys em Vercel Hobby (10s) vão falhar imediatamente em batch settlements. Em Pro (60s), acima de ~300 settlements/batch → função morta silenciosamente, settlements parciais, estado inconsistente.

## Correção proposta

1. Processar em chunks: `LIMIT 50` por invocação, continuação via cron `/api/cron/settle-clearing-batch` a cada minuto.
  2. Para exports: usar Supabase Edge Function (Deno, timeout 150s) em vez de Next.js API.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.10).
- `2026-04-20` — **Fix entregue.** Migration
  `20260420100000_l02_clearing_settle_chunked.sql` introduz
  `fn_settle_clearing_chunk` (bounded por `LIMIT`, `FOR UPDATE SKIP
  LOCKED`, exception per-row) + `fn_settle_clearing_batch_safe` (cron-safe
  wrapper integrado ao `cron_run_state` da L12-03) + `pg_cron` schedule
  `settle-clearing-batch` rodando a cada minuto direto no banco.
  Helper `settleClearingChunk` em `portal/src/lib/clearing.ts` substitui
  o `settleWindowForDebtor` (mantido como `@deprecated`). Surface de
  replay manual `POST /api/cron/settle-clearing-batch` autenticada por
  `CRON_SECRET` (timing-safe compare), com soft-time-budget de 50s e
  drain-loop bounded. CSP/CSRF/route-policy ajustados (`/api/cron/`
  como `PUBLIC_PREFIX` + CSRF-exempt). Runbook atualizado em
  `docs/runbooks/CRON_HEALTH_RUNBOOK.md` §3.5. Cobertura: 9 integration
  tests (`tools/test_l02_10_clearing_settle_chunked.ts`) + 40 vitest
  (helper + route).