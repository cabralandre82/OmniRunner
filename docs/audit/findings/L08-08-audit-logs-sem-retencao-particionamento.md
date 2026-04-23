---
id: L08-08
audit_ref: "8.8"
lens: 8
title: "audit_logs sem retenção / particionamento"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["lgpd", "migration", "cron", "reliability", "partitioning"]
files:
  - supabase/migrations/20260421400000_l08_08_audit_logs_retention.sql
  - tools/audit/check-audit-logs-retention.ts
  - docs/runbooks/AUDIT_LOGS_RETENTION_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/audit/check-audit-logs-retention.ts
linked_issues: []
linked_prs:
  - local:d64b72e
owner: platform
runbook: docs/runbooks/AUDIT_LOGS_RETENTION_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Shipped the retention primitives + a monthly partition creator.
  Conversion of live `public.audit_logs` to RANGE PARTITIONED is
  tracked as follow-up `L08-08-partition-audit-logs` (maintenance
  window required; retention alone already reclaims space). Runbook
  `docs/runbooks/AUDIT_LOGS_RETENTION_RUNBOOK.md` carries the full
  LGPD / fiscal matrix (730d for audit_logs, 1825d for fiscal rows,
  NULL forever for consent_events).
---
# [L08-08] audit_logs sem retenção / particionamento
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** —
**Personas impactadas:** —
## Achado
— Tabela cresce indefinidamente. Sem particionamento por mês.
## Risco / Impacto

— Após 2 anos: 100M+ rows, queries de compliance levam minutos, backups inchados.

## Correção proposta

—

```sql
-- Partition by month
CREATE TABLE audit_logs_new (...) PARTITION BY RANGE (created_at);
-- Migrate data; create 24 monthly partitions ahead.
-- pg_cron: drop partitions older than 2 years (LGPD justifica retenção por auditoria fiscal; 5 anos para dados fiscais).
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.8).
- `2026-04-21` — **Resolvido** (fix commit). Migração `20260421400000_l08_08_audit_logs_retention.sql` entrega: (a) tabela `audit_logs_retention_config` com janela por tabela (LGPD/fiscal: 730d audit_logs, 1825d custody/coin_ledger_pii_redactions, NULL=forever consent_events, 90d cron_edge_retry_attempts, 365d wallet_drift_events, 730d portal_audit_log); (b) `audit_logs_retention_runs` append-only registrada na config L10-08; (c) `fn_audit_retention_delete_batch` com bypass **DELETE-only** via `SET LOCAL audit.retention_pass='on'` (UPDATE e TRUNCATE continuam bloqueados mesmo com GUC setado); (d) `fn_audit_retention_run_all` com `pg_try_advisory_xact_lock` + tolerância per-table; (e) `fn_audit_ensure_monthly_partition` no-op para tabelas heap (pronta para o follow-up de partição); (f) pg_cron diário 05:15 UTC + mensal dia 25 às 02:00 UTC. CI guard `npm run audit:audit-logs-retention` (55 invariantes estáticos). Self-test da migration prova: (i) UPDATE nunca é bypass-ável; (ii) DELETE sem bypass é bloqueado; (iii) consent_events retorna `skipped_no_retention`. Runbook `AUDIT_LOGS_RETENTION_RUNBOOK.md` (~10 KB) com matriz legal, 5 playbooks ops e follow-ups explícitos (conversão de `audit_logs` para RANGE partitioned como `L08-08-partition-audit-logs`, janela de manutenção). Decisões arquiteturais: (1) retenção hoje, particionamento depois — reclama espaço imediatamente sem exclusive lock; (2) bypass via GUC txn-local em vez de ALTER TABLE DISABLE TRIGGER — sem lock, auditável, reverte automaticamente no COMMIT; (3) seed cobre 7 tabelas de auditoria conhecidas, todas já protegidas por L10-08; (4) conversão live da `audit_logs` para partição fica explicitamente fora — primitives hoje, follow-up quando volume passar 50M rows. Cross-refs: L10-08 (sibling append-only, esta migration atualiza `fn_audit_reject_mutation` aditivamente), L19-06 (GIN index — precisará ser recriado por partição após conversão), L04-07 (coin_ledger_pii_redactions compartilha 5 anos fiscal), L06-04 (cron-health-monitor alerta se o cron parar), L18-03 (SECURITY DEFINER com search_path explícito).