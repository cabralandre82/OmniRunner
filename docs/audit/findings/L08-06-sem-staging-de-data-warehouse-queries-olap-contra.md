---
id: L08-06
audit_ref: "8.6"
lens: 8
title: "Sem staging de data warehouse — queries OLAP contra OLTP"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "mobile"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L08-06] Sem staging de data warehouse — queries OLAP contra OLTP
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Dashboards `/platform/*` rodam `SELECT` pesados diretamente em `custody_accounts`, `coin_ledger`, `sessions` via Supabase. Sem isolamento de carga.
## Risco / Impacto

— Dashboard pesado em hora de pico trava RPC crítico (execute_burn_atomic espera por lock). Incidente em produção causado por BI.

## Correção proposta

— Supabase Foreign Data Wrapper ou pg_logical replication para **réplica dedicada OLAP** (mesmo que seja o mesmo cluster Postgres com replica). Ou export incremental noturno para DuckDB/BigQuery.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.6).