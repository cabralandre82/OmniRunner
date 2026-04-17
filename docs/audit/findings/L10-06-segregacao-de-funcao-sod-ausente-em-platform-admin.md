---
id: L10-06
audit_ref: "10.6"
lens: 10
title: "Segregação de função (SoD) ausente em platform_admin"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "migration", "reliability"]
files: []
correction_type: config
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
# [L10-06] Segregação de função (SoD) ausente em platform_admin
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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