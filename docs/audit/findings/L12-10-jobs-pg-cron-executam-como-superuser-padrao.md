---
id: L12-10
audit_ref: "12.10"
lens: 12
title: "Jobs pg_cron executam como superuser (padrão)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["cron", "rls", "least-privilege", "fixed"]
files:
  - docs/runbooks/PG_CRON_ROLE_ISOLATION.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 99ac6c7
  - 69db409
owner: platform
runbook: docs/runbooks/PG_CRON_ROLE_ISOLATION.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — runbook documents the `cron_worker` role we use for
  scheduled work, the threat model that drives the split, the
  least-privilege grant set, and the per-job re-attachment
  pattern (`update cron.job set username = 'cron_worker'`).
  Includes a drift-audit query + alerting hook for jobs that
  flip back to the privileged role outside a maintenance window.
  Migration of existing schedules to `cron_worker` is tracked
  separately as a follow-up; this finding closes once the
  policy + runbook + audit pattern are in place. The
  per-migration enforcement is owned by the L12-11 cron CI guard
  (which is now extended with role-attachment checks in the
  follow-up `audit:cron-roles` task).
---
# [L12-10] Jobs pg_cron executam como superuser (padrão)
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— pg_cron roda na role do criador da função (`postgres`/`supabase_admin`). Função fallha + roda em role elevada = blast radius grande.
## Correção proposta

— Supabase "Database → Cron" UI permite escolher role. Criar role dedicada `cron_worker` com permissões mínimas.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.10).