---
id: L01-43
audit_ref: "1.43"
lens: 1
title: "custody_accounts RLS — role 'professor' nunca corresponde"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "rls", "mobile", "migration", "reliability", "fixed"]
files:
  - supabase/migrations/20260228150001_custody_clearing_model.sql
  - supabase/migrations/20260303300000_fix_coaching_roles.sql
  - supabase/migrations/20260421770000_l01_43_dead_role_audit.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - supabase/migrations/20260421770000_l01_43_dead_role_audit.sql
linked_issues: []
linked_prs:
  - aa816fb
  - 8c62f60
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — dead-role purge: 20260303300000 already DROP/CREATE-d the
  affected RLS policies (custody_accounts, custody_deposits, clearing_events)
  replacing 'professor' with 'coach'. This finding adds a runtime self-test
  migration that scans pg_policies for any live policy still referencing
  the dead role and aborts deploy if any is found — guaranteeing the fix
  holds at the production database level (not just in source files).
---
# [L01-43] custody_accounts RLS — role 'professor' nunca corresponde
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** admin_master, coach
## Achado
`supabase/migrations/20260228150001_custody_clearing_model.sql:59-67`:
  ```sql
  CREATE POLICY "custody_own_group_read" ON public.custody_accounts
    FOR SELECT USING (... AND cm.role IN ('admin_master', 'professor'))
  ```
  Mas o role canônico é `'coach'` (migration 20260304050000 migrou `professor → coach`). **Essa policy foi esquecida pela migration 20260321** (que consertou outras). Resultado: clients com RLS enabled (não service_role) nunca veem custody_accounts se forem `coach`. Como todo o código atual usa `createServiceClient()`, o bug é silencioso — mas **dead policy** acumula e qualquer read feito via auth.client falha.
## Risco / Impacto

Bug latente; developers inexperientes tentando refatorar para uso correto de RLS vão enfrentar "empty results" sem erro.

## Correção proposta

Nova migration:
  ```sql
  DROP POLICY IF EXISTS "custody_own_group_read" ON public.custody_accounts;
  CREATE POLICY "custody_own_group_read" ON public.custody_accounts
    FOR SELECT USING (
      EXISTS (SELECT 1 FROM coaching_members cm
        WHERE cm.group_id = custody_accounts.group_id
          AND cm.user_id = auth.uid()
          AND cm.role IN ('admin_master', 'coach'))
    );
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.43]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.43).