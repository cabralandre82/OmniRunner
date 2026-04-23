---
id: L10-06
audit_ref: "10.6"
lens: 10
title: "Segregação de função (SoD) ausente em platform_admin"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "migration", "reliability"]
files:
  - supabase/migrations/20260421510000_l10_06_admin_approvals_sod.sql
  - tools/audit/check-admin-approvals-sod.ts
correction_type: config
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:fd950f8
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  admin_approvals queue + BEFORE UPDATE trigger enforce two-
  person rule on high-risk platform_admin actions:
  platform_fee_config / admin-grant / billing_provider key
  mutations always require a second distinct admin;
  withdrawals and refunds require dual approval above
  US$ 10k. Self-approval blocked by CHECK at INSERT time and
  re-asserted by trigger to cover service-role paths.
  `status = 'executed'` requires prior `status = 'approved'`,
  and terminal statuses are locked. 24h TTL enforced by
  fn_admin_approvals_expire_overdue (cron target). Ships with
  audit:admin-approvals-sod guard (27 invariants).
---
# [L10-06] Segregação de função (SoD) ausente em platform_admin
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `platform_admin` pode: (a) configurar taxas, (b) executar withdrawals manuais, (c) criar refunds. Um único usuário comprometido move toda a tesouraria. Sem aprovação dupla.
## Correção proposta

—

```sql
CREATE TABLE public.admin_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action_type text NOT NULL,
  payload jsonb NOT NULL,
  requested_by uuid NOT NULL,
  approved_by uuid,
  rejected_by uuid,
  status text DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','executed','expired')),
  expires_at timestamptz DEFAULT (now() + interval '24 hours'),
  executed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT chk_self_approval CHECK (approved_by IS NULL OR approved_by <> requested_by)
);
```

Ações ≥ US$ 10k ou mudança de platform_fee_config exigem duas linhas distintas (requester + approver) antes de `status = 'executed'`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.6).