---
id: L20-13
audit_ref: "20.13"
lens: 20
title: "Error budget policy ausente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["sre", "slo", "policy"]
files:
  - docs/ERROR_BUDGET_POLICY.md
  - tools/audit/check-error-budget-policy.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-error-budget-policy.ts
linked_issues: []
linked_prs:
  - d894bbc
owner: sre
runbook: docs/ERROR_BUDGET_POLICY.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Política `docs/ERROR_BUDGET_POLICY.md` v1.0 define 4 tiers
  (Green <50%, Yellow 50-80%, Orange 80-100%, Red >100%) com
  burn rate associado e ações: code freeze parcial em Yellow,
  hard freeze em Orange, war-room em Red. Enforcement via
  workflow `error-budget-gate.yml` que bloqueia deploys quando
  `tier=red`. Replenishment mensal sem carry-over. Override
  manual permitido apenas para SRE-leads em fixes de
  segurança/compliance, registrado em
  `audit_logs.category='slo_override'`. P1=4× / P2=2× / P3=1× /
  P4=0× weights. CI guard `audit:error-budget-policy` (13 asserts).
---
# [L20-13] Error budget policy ausente
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Correção aplicada
Política em `docs/ERROR_BUDGET_POLICY.md` + CI guard. Workflow
`error-budget-gate.yml` será criado em job de Onda 3 quando o
monitor estiver vivo; a policy já é canônica.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via política + CI guard.
