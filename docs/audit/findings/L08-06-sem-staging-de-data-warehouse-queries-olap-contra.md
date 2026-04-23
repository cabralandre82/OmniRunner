---
id: L08-06
audit_ref: "8.6"
lens: 8
title: "Sem staging de data warehouse — queries OLAP contra OLTP"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "atomicity", "mobile", "platform", "olap"]
files:
  - supabase/migrations/20260421410000_l08_06_olap_staging.sql
  - tools/audit/check-olap-staging.ts
  - docs/runbooks/OLAP_STAGING_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/audit/check-olap-staging.ts
linked_issues: []
linked_prs:
  - local:06b4087
owner: platform
runbook: docs/runbooks/OLAP_STAGING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Entregue como camada de staging `public_olap.*` (MVs + pg_cron), não como
  réplica dedicada. Dashboards `/platform/*` migram incrementalmente para
  ler as MVs. Follow-ups registrados: `L08-06-read-replica` (infra,
  substituir/complementar com pg_logical) e `L08-06-portal-migrate`
  (migrar consumidores).
---
# [L08-06] Sem staging de data warehouse — queries OLAP contra OLTP
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** plataforma (DB) · **Personas impactadas:** staff, assessorias (dashboard)

## Achado
Dashboards `/platform/*` rodam `SELECT` pesados diretamente em `custody_accounts`,
`coin_ledger`, `sessions` via Supabase. Sem isolamento de carga.

## Risco / Impacto
Dashboard pesado em hora de pico trava RPC crítico (`execute_burn_atomic` espera
por lock). Incidente em produção causado por BI.

## Correção entregue (2026-04-21)
Camada de staging OLAP `public_olap.*` no mesmo cluster, complementar a uma
futura réplica dedicada:

- **Schema `public_olap`** — `USAGE` apenas para `service_role`; `anon` /
  `authenticated` / `PUBLIC` explicitamente revogados.
- **Três materialized views iniciais**, cobrindo os hotspots hoje:
  - `mv_sessions_completed_daily` (status≥3 agregado por dia UTC)
  - `mv_coin_ledger_daily_by_reason` ((dia, reason) → count, sum_delta)
  - `mv_custody_accounts_snapshot` (um registro por grupo)
  - Cada MV com `UNIQUE INDEX` — requisito de `REFRESH CONCURRENTLY`.
- **`mv_refresh_config`** — por-MV: `refresh_interval_seconds`
  (60..86400), `statement_timeout_ms` (1000..600000), `enabled`, `concurrent`.
  RLS forçado, `service_role`-only.
- **`mv_refresh_runs`** — trilha append-only (registrada em L10-08).
  `status` whitelist: `ok`, `skipped_disabled`, `skipped_no_mv`,
  `skipped_no_config`, `skipped_locked`, `skipped_too_soon`, `error`.
- **`fn_refresh_mv(mv_name)`** — SECURITY DEFINER, `set_config('statement_timeout',
  …, true)` txn-local, advisory lock por MV, too-soon guard, auto-detecta
  `ispopulated` para evitar CONCURRENTLY no primeiro refresh.
- **`fn_refresh_all()`** — dispatcher com advisory lock global; erro numa
  MV não derruba as outras.
- **pg_cron `olap-refresh-all`** a cada 15 minutos.
- **Self-test** na própria migration: refresh inexistente → `skipped_no_config`;
  segundo imediato → `skipped_too_soon`; DELETE em `mv_refresh_runs` → `P0010`.
- **CI guard `audit:olap-staging`** (66 invariantes) + runbook completo em
  [`docs/runbooks/OLAP_STAGING_RUNBOOK.md`](../../runbooks/OLAP_STAGING_RUNBOOK.md).

### O que NÃO está nesta entrega (follow-ups)
- Réplica dedicada OLAP (pg_logical / FDW / DuckDB / BigQuery) — requer
  janela de manutenção e recursos de infra. Tracked: `L08-06-read-replica`.
- Migração dos consumidores `/platform/*` para apontar às MVs — PRs de
  portal incrementais. Tracked: `L08-06-portal-migrate`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.6]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.6).
- `2026-04-21` — **fixed**: staging OLAP (`public_olap.*`) + pg_cron +
  CI guard + runbook. Réplica dedicada fica como follow-up de infra.