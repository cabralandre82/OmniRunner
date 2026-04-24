---
id: L03-08
audit_ref: "3.8"
lens: 3
title: "Custody check_custody_invariants — Valida R_i vs M_i mas não total_settled"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "migration", "reliability", "invariants", "fixed"]
files:
  - supabase/migrations/20260228170000_custody_gaps.sql
  - supabase/migrations/20260421790000_l03_08_global_conservation_check.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - "supabase/migrations/20260421790000_l03_08_global_conservation_check.sql (in-migration self-test)"
  - "npm run audit:k2-sql-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — adds the third invariant check ("Check 3: global USD
  conservation") to public.check_custody_invariants(). It compares
  SUM(custody_accounts.total_deposited_usd) against
    SUM(confirmed deposits) − SUM(completed withdrawals)
                                              − SUM(platform_revenue)
  and emits a row tagged 'global_deposit_mismatch' whenever |diff| > 0.01.
  Tolerance is 1¢ to absorb ROUND noise from settlement. CI guard asserts
  the new check is present in pg_get_functiondef.
---
# [L03-08] Custody check_custody_invariants — Valida R_i vs M_i mas não total_settled
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Plataforma
## Achado
`20260228170000:273-322` valida:
  1. `committed ≥ 0`, `deposited ≥ 0`, `deposited ≥ committed`.
  2. `total_committed = SUM(coin_ledger.delta_coins WHERE issuer=X)`.
## Risco / Impacto

Drift acumulativo não-detectado. Após meses, somas globais divergem da contabilidade sintética.

## Correção proposta

Expandir `check_custody_invariants` com conservação global:
```sql
-- Check 3: global conservation
SELECT NULL::uuid, ..., 'global_deposit_mismatch'
WHERE (SELECT SUM(total_deposited_usd) FROM custody_accounts)
   <> (SELECT SUM(amount_usd) FROM custody_deposits WHERE status='confirmed')
      - (SELECT SUM(amount_usd) FROM custody_withdrawals WHERE status='completed')
      - (SELECT SUM(amount_usd) FROM platform_revenue);
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.8).