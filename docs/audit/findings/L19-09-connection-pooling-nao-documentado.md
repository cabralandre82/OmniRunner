---
id: L19-09
audit_ref: "19.9"
lens: 19
title: "Connection pooling não documentado"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["dba", "runbook", "documentation"]
files:
  - docs/runbooks/CONNECTION_POOLING.md
  - tools/audit/check-connection-pooling.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-connection-pooling.ts
linked_issues: []
linked_prs: []
owner: platform
runbook: docs/runbooks/CONNECTION_POOLING.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Runbook `docs/runbooks/CONNECTION_POOLING.md` v1.0 documenta:
  topologia (Vercel + EF → pgBouncer transaction mode → Postgres);
  pool sizes por tier (Free 60 / Pro 200 / Team 400 / Enterprise
  1000); rationale para transaction mode; failure modes
  (remaining connection slots / ETIMEDOUT / burst de digest);
  observability (`pg_stat_activity` snapshots em audit_logs).
  CI guard `audit:connection-pooling` (11 asserts).
---
# [L19-09] Connection pooling não documentado
> **Lente:** 19 — DBA · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Correção aplicada
Runbook completo em `docs/runbooks/CONNECTION_POOLING.md`. CI
guard `audit:connection-pooling` (11 asserts) bloqueia drift.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via runbook + CI guard.
