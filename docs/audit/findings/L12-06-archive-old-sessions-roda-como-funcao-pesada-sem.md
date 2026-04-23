---
id: L12-06
audit_ref: "12.6"
lens: 12
title: "archive-old-sessions roda como função pesada sem batch"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["atomicity"]
files:
  - "supabase/migrations/20260421250000_l12_06_archive_sessions_chunked_commits.sql"
  - "supabase/functions/archive-old-sessions/index.ts"
  - "tools/test_l12_06_archive_sessions_chunked.ts"
  - "docs/runbooks/ARCHIVE_OLD_SESSIONS_RUNBOOK.md"
correction_type: code
test_required: true
tests:
  - "tools/test_l12_06_archive_sessions_chunked.ts"
linked_issues: []
linked_prs: ["d8b0e10"]
owner: coo
runbook: "docs/runbooks/ARCHIVE_OLD_SESSIONS_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L12-06] archive-old-sessions roda como função pesada sem batch
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** backend/db
**Personas impactadas:** COO, CTO, DBA

## Achado
— `fn_archive_old_sessions()` provavelmente move linhas para partição fria/S3 de uma só vez. Sem `LIMIT` por execução, lock longo de `sessions`.

## Correção proposta

— Loop em batch de 1000 + `COMMIT` entre batches (via function autonomous transactions ou DO block com savepoints).

## Correção aplicada

1. **Novo primitive `public.fn_archive_sessions_chunk(batch_size, cutoff_months)`** (`SECURITY DEFINER`, `lock_timeout=2s`): processa exatamente um chunk — `DELETE ... RETURNING` em CTE + `INSERT INTO sessions_archive`, devolvendo `jsonb` com `moved_count`, `more_pending`, `duration_ms`, `cutoff_ms`. Valida `batch_size ∈ [1,10000]` e `cutoff_months ∈ [1,120]` com `ERRCODE 22023`.
2. **Novo helper `public.fn_archive_sessions_pending_count(cutoff_months)`** (`STABLE`, `SECURITY DEFINER`): expõe o backlog ao painel de operações sem bloquear a tabela.
3. **Edge Function `supabase/functions/archive-old-sessions/index.ts`**: orquestra o loop chamando `fn_archive_sessions_chunk` via RPC. Cada RPC é **uma transação Postgres separada**, garantindo COMMIT entre chunks, liberando locks e permitindo autovacuum rodar no intervalo. Parâmetros configuráveis: `batch_size` (default 500), `cutoff_months` (6), `max_batches` (40), `max_duration_ms` (480000, teto de 540000). Retorna `rows_moved_total`, `batches`, `duration_ms`, `terminated_by ∈ {no_more_pending, max_batches, max_duration}`.
4. **Shim de retrocompatibilidade**: `public.fn_archive_old_sessions()` foi reescrita para chamar internamente `fn_archive_sessions_chunk` em loop (batches de 250, cutoff 6 meses), preservando a assinatura `RETURNS integer` e o comportamento de transação única para chamadores diretos (psql operacional, scripts legados).
5. **Novo entry point de cron `public.fn_invoke_archive_sessions_safe`**: integra com `cron_run_state` (L12-03), tenta a Edge Function via `fn_invoke_edge_with_retry` (L06-05) — que já gera `cron_health_alerts` em falha permanente — e cai para o shim SQL se `http`/`pg_net` estiverem ausentes ou a Edge falhar. Registra `last_meta.mode ∈ {edge_function, sql_fallback}` para auditoria.
6. **Cron rescheduled**: `SELECT cron.unschedule('archive-old-sessions')` seguido de `cron.schedule('archive-old-sessions', '45 3 * * 0', 'SELECT public.fn_invoke_archive_sessions_safe();')` — mantém a janela Sun 03:45 UTC (escolhida em L12-02 para evitar o herd das 03:00).
7. **Grants**: todas as quatro funções têm `REVOKE ALL ... FROM PUBLIC` + `GRANT EXECUTE ... TO service_role`. Self-test em `DO $$ ... $$` no fim da migration valida registros em `pg_proc`, `cron.job` e assinatura de `jsonb`.

### Impacto mensurável
- Antes: uma única transação de ~30 min segurando locks em `public.sessions`, bloqueando autovacuum até a função retornar.
- Depois: chunks de 500 linhas (~1-2 s cada) commitam em sequência; autovacuum pode intervir entre chunks, mid-run kill preserva progresso parcial.

### Testes
`tools/test_l12_06_archive_sessions_chunked.ts` (13 casos, todos passando) cobre DDL/grants/cron schedule, validação de argumentos (0/20000 batch_size, 0/999 cutoff_months → 22023), shape do jsonb retornado em janela vazia, tipo integer do shim e bigint não-negativo do pending_count.

### Runbook
`docs/runbooks/ARCHIVE_OLD_SESSIONS_RUNBOOK.md` — dashboard queries, cenários (backlog crescendo, falhas do Edge, ad-hoc, abort), tunables e rollback.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.6).
- `2026-04-21` — Correção aplicada (`d8b0e10`): chunk primitive + Edge orchestrator + safe wrapper + shim + runbook + 13 testes.
