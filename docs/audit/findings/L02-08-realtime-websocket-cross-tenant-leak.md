---
id: L02-08
audit_ref: "2.8"
lens: 2
title: "Realtime / Websocket — Cross-tenant leak"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "rls", "mobile", "migration", "reliability"]
files:
  - supabase/migrations/20260419160000_l02_realtime_rls_guard.sql
correction_type: process
test_required: true
tests:
  - tools/test_l02_realtime_rls_guard.ts
linked_issues: []
linked_prs:
  - "commit:ef42911"
owner: dba-team
runbook: docs/runbooks/REALTIME_RLS_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed via defence-in-depth in `supabase/migrations/20260419160000_l02_realtime_rls_guard.sql`:

  1. `public.realtime_publication_allowlist` table captures intentional
     global-broadcast tables (seeded with `feature_flags` for L18-06).
     `reason` column is NOT NULL with a `length(trim(reason)) >= 10`
     CHECK so every exemption carries an audit-grade justification.

  2. `public.fn_realtime_publication_unsafe_tables(p_publication)` —
     diagnostic that returns one row per offender with a machine-
     readable reason (`rls_disabled`, `no_select_policy`,
     `tautological_select_policy_using_true`).

  3. `public.fn_assert_realtime_publication_safe(p_publication)` —
     wraps the diagnostic and RAISES `P0009 REALTIME_RLS_VIOLATION`
     with a HINT pointing at the runbook.

  4. **DDL event trigger** `trg_block_unsafe_realtime_publication` on
     `ddl_command_end` filtered to `ALTER PUBLICATION` /
     `CREATE PUBLICATION`. Re-runs the guard in the same transaction;
     any failure rolls the publication change back. This is the
     enforcement primitive — even a Supabase dashboard click cannot
     bypass it.

  5. Self-test at migration time iterates current offenders and emits
     `[L02-08.violation]` RAISE NOTICE entries; deliberately
     non-fatal so the migration can apply against environments with
     pre-existing publication state. Operators triage post-apply.

  Tested by `tools/test_l02_realtime_rls_guard.ts` (8 cases: clean
  baseline, diagnostic flagging, allow-list bypass, P0009 from the
  assertion, four event-trigger scenarios). Operational guide in
  `docs/runbooks/REALTIME_RLS_RUNBOOK.md` covers add-a-table flow,
  allow-list flow, and triage of `P0009` errors.
---
# [L02-08] Realtime / Websocket — Cross-tenant leak
> **Lente:** 2 — CTO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** APP (Flutter via `supabase_flutter`) + BACKEND
**Personas impactadas:** Atleta, Assessoria
## Achado
O projeto usa Realtime (pubspec declara `supabase_flutter`). Tabelas adicionadas a `supabase_realtime` vazam se RLS não filtrar nos eventos. Não verifiquei migration `supabase_realtime` direto, mas o padrão genérico é: Realtime aplica RLS via `auth.uid()` do subscriber. As policies `custody_accounts` estão com role `'professor'` (ver [1.43]) → **atletas e coaches nunca recebem eventos de custody** (bem). Porém, policies de `coaching_members`, `wallets`, `sessions` podem permitir vazamento — atleta A inspeciona seu cliente WebSocket e altera filtros para receber eventos de atleta B. RLS em `wallets` precisa restringir a `user_id = auth.uid()`.
## Risco / Impacto

Vazamento de saldo, sessão, ranking por inspeção de WebSocket.

## Correção proposta

Auditar cada tabela com REPLICA IDENTITY ou em `ALTER PUBLICATION supabase_realtime ADD TABLE X`. Confirmar RLS FOR SELECT é restritivo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.8).
- `2026-04-17` — Corrigido via guard SQL + DDL event trigger + allow-list. Migration `20260419160000_l02_realtime_rls_guard.sql`, runbook `docs/runbooks/REALTIME_RLS_RUNBOOK.md`, integration tests `tools/test_l02_realtime_rls_guard.ts`.