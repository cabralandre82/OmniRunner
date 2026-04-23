---
id: L19-08
audit_ref: "19.8"
lens: 19
title: "Constraints CHECK sem name padronizado"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "migration"]
files:
  - supabase/migrations/20260421290000_l19_08_check_constraint_naming.sql
  - tools/audit/check-constraint-naming.ts
  - tools/test_l19_08_check_constraint_naming.ts
  - tools/test_l04_07_ledger_reason_pii.ts
  - package.json
  - docs/runbooks/DB_CHECK_CONSTRAINT_NAMING_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l19_08_check_constraint_naming.ts
linked_issues: []
linked_prs:
  - 44cd970
owner: platform-db
runbook: docs/runbooks/DB_CHECK_CONSTRAINT_NAMING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L19-08] Constraints CHECK sem name padronizado
> **Lente:** 19 — DBA · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** DB
**Personas impactadas:** operação, DBA, SRE
## Achado
— Algumas tabelas têm `chk_peg_1_to_1`, outras usam nome auto-gerado `custody_accounts_total_deposited_usd_check`. Em erros, frontend mostra nome feio.

## Correção aplicada (2026-04-21)
Convenção forward-only aceita **dois** padrões:
- (A) `<table>_<col>_check` — auto-gerado pelo Postgres (informativo, mantido por replay-safety)
- (B) `chk_<table>_<rule>` — ad-hoc explícito

4 constraints ad-hoc sem prefixo foram renomeadas em migração idempotente:
- `clearing_settlements.different_groups` → `chk_clearing_settlements_distinct_groups`
- `swap_orders.swap_different_groups` → `chk_swap_orders_distinct_groups`
- `coin_ledger.coin_ledger_reason_length_guard` → `chk_coin_ledger_reason_length_guard`
- `coin_ledger.coin_ledger_reason_pii_guard` → `chk_coin_ledger_reason_pii_guard`

Detecção programática:
- `public.fn_find_nonstandard_check_constraints(schema, table)` — lista violações.
- `public.fn_assert_check_constraints_standardized(schemas[], tables[])` — raises P0010.
- CI: `npm run audit:constraint-naming` (16 tabelas financeiras).

Runbook: [`DB_CHECK_CONSTRAINT_NAMING_RUNBOOK.md`](../../runbooks/DB_CHECK_CONSTRAINT_NAMING_RUNBOOK.md)

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.8).
- `2026-04-21` — Corrigido (commit `44cd970`): convenção + detector + CI + rename de 4 constraints.