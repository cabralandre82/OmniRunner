---
id: L19-06
audit_ref: "19.6"
lens: 19
title: "JSONB em audit_logs.metadata sem índice GIN"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["performance"]
files:
  - supabase/migrations/20260421300000_l19_06_audit_logs_metadata_gin.sql
  - tools/audit/check-audit-logs-gin.ts
  - tools/test_l19_06_audit_logs_metadata_gin.ts
  - package.json
  - docs/runbooks/AUDIT_LOGS_METADATA_GIN_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l19_06_audit_logs_metadata_gin.ts
linked_issues: []
linked_prs:
  - 271c549
owner: platform-dba
runbook: docs/runbooks/AUDIT_LOGS_METADATA_GIN_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L19-06] JSONB em audit_logs.metadata sem índice GIN
> **Lente:** 19 — DBA · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** DB
**Personas impactadas:** platform-admin, SRE, DBA
## Achado
— Queries "todos eventos do request_id X" fazem seq scan.

## Correção aplicada (2026-04-21)
Migração defensiva `20260421300000_l19_06_audit_logs_metadata_gin.sql`:
- Cria `idx_audit_logs_metadata_gin` `USING GIN (metadata jsonb_path_ops)`
  **apenas se** `public.audit_logs` existir com coluna `metadata jsonb`
  (no-op em sandboxes/ambientes parciais).
- Operador `jsonb_path_ops` em vez do default `jsonb_ops` — suporta `@>`
  (único operador usado), gera índice ~30% menor.
- Dois helpers SECURITY DEFINER (EXECUTE só para `service_role`):
  - `fn_audit_logs_has_metadata_gin()` — boolean detector.
  - `fn_audit_logs_assert_metadata_gin()` — raise `P0010` com HINT
    se a tabela+coluna existem mas o índice falta.
- CI: `npm run audit:audit-logs-gin` (no-op quando `audit_logs` ausente).
- `CREATE INDEX` não-CONCURRENTLY porque migrations rodam em transação;
  runbook documenta o playbook out-of-band com CONCURRENTLY para bases
  com > 10M linhas.

Query patterns canônicos documentados no runbook (apenas `@>`):

```sql
SELECT * FROM audit_logs WHERE metadata @> '{"request_id": "..."}';
SELECT * FROM audit_logs WHERE metadata @> '{"session_id": "..."}';
SELECT * FROM audit_logs WHERE metadata @> '{"correlation_id": "..."}';
```

Runbook: [`AUDIT_LOGS_METADATA_GIN_RUNBOOK.md`](../../runbooks/AUDIT_LOGS_METADATA_GIN_RUNBOOK.md)

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.6).
- `2026-04-21` — Corrigido (commit `271c549`): defensive GIN + detector/assert + CI.