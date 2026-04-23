---
id: L10-08
audit_ref: "10.8"
lens: 10
title: "Logs de acesso sensíveis sem imutabilidade"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["audit", "security", "database"]
files:
  - supabase/migrations/20260421350000_l10_08_audit_logs_append_only.sql
  - tools/audit/check-audit-logs-append-only.ts
  - tools/test_l10_08_audit_logs_append_only.ts
  - docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l10_08_audit_logs_append_only.ts
linked_issues: []
linked_prs:
  - 0e13ba8
owner: platform
runbook: docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "2026-04-21 — fixed. public.audit_append_only_config registry + fn_audit_reject_mutation BEFORE UPDATE/DELETE/TRUNCATE trigger (P0010) installed on portal_audit_log, coin_ledger_pii_redactions, cron_edge_retry_attempts, consent_events. account_deletion_log registered as append_with_outcome. CI npm run audit:audit-logs-append-only + runbook."
---
# [L10-08] Logs de acesso sensíveis sem imutabilidade
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `audit_logs` é tabela normal; atacante com service-role pode `DELETE`/`UPDATE`.
## Correção proposta

—

1. Role `audit_read_only` com `GRANT SELECT` apenas.
2. Trigger `BEFORE DELETE OR UPDATE ON audit_logs` que bloqueia operações.
3. Export incremental para S3 com Object Lock (compliance mode) — 7 anos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.8).
- `2026-04-21` — Corrigido. `public.audit_append_only_config` rastreia cada tabela de auditoria protegida (`portal_audit_log`, `coin_ledger_pii_redactions`, `cron_edge_retry_attempts`, `consent_events`, `wallet_drift_events`/`custody_daily_cap_changes`/`audit_logs` quando presentes). `fn_audit_reject_mutation` BEFORE UPDATE/DELETE/TRUNCATE dispara `P0010` com reason codes (`append_only_delete_blocked`/`append_only_update_blocked`/`append_only_truncate_blocked`) e emite `RAISE WARNING` com `session_user`/`current_user` para Logflare. `account_deletion_log` fica como `append_with_outcome` (trigger próprio L04-02). Helpers `fn_audit_install_append_only_guard`, `fn_audit_has_append_only_guard` e `fn_audit_assert_append_only_shape` (usado por `npm run audit:audit-logs-append-only`). Testes em `tools/test_l10_08_audit_logs_append_only.ts`. Runbook `docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md`.