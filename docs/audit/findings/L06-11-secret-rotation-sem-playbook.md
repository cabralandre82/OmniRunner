---
id: L06-11
audit_ref: "6.11"
lens: 6
title: "Secret rotation sem playbook"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["security", "secrets", "runbook", "process"]
files:
  - docs/runbooks/SECRET_ROTATION_RUNBOOK.md
  - tools/audit/check-secret-rotation.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-secret-rotation.ts
linked_issues: []
linked_prs:
  - d894bbc
owner: platform
runbook: docs/runbooks/SECRET_ROTATION_RUNBOOK.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Runbook `docs/runbooks/SECRET_ROTATION_RUNBOOK.md` v1.0
  inventaria todos os 10 secrets críticos (SUPABASE_*, STRIPE_*,
  MP_*, ASAAS_*, STRAVA_*, TRAININGPEAKS_*, SENTRY_*, VERCEL_*,
  JWT_*) com cadência (90d default, 180d para service_role,
  365d para OAuth/SDK), procedimento universal em 5 passos com
  slot `_NEXT/_PREV` para zero-downtime, playbooks específicos
  para STRIPE/MP/ASAAS, template de maintenance window para
  providers sem dual-key. Emergency rotation 30min SLA. Cadence
  monitor (job daily) abre P3 com 90% e P2 com 100% expirado.
  CI guard `audit:secret-rotation` (17 asserts).
---
# [L06-11] Secret rotation sem playbook
> **Lente:** 6 — COO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Correção aplicada
Runbook completo + CI guard. Próximo passo: implementar
`secret-rotation-cadence-monitor` job (Onda 3).

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via runbook + CI guard.
