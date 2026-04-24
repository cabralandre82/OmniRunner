---
id: L08-11
audit_ref: "8.11"
lens: 8
title: "Feature flags (quando [6.6] implementar) precisam de metrics"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: []
files:
  - docs/runbooks/FEATURE_FLAG_AUDIT.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs:
  - d3488b4
  - ba3c71e
owner: platform
runbook: docs/runbooks/FEATURE_FLAG_AUDIT.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Codified in docs/runbooks/FEATURE_FLAG_AUDIT.md the audit
  contract that the future L06-06 feature-flag service must
  honour: trigger fn_audit_feature_flag_change writes
  audit_logs row with event_domain='feature_flag' and
  before_value/after_value jsonb on every INSERT/UPDATE/DELETE,
  actor_kind='system' for SLO auto-rollbacks (L01-49 taxonomy),
  metrics.feature_flag.toggle counter for SRE dashboard,
  fn_feature_flag_history admin-only RPC for the dashboard,
  with regression test plan.
---
# [L08-11] Feature flags (quando [6.6] implementar) precisam de metrics
> **Lente:** 8 — CDO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Implementação proposta sem auditar quem mudou e quando.
## Correção proposta

— Trigger em `feature_flags` gravando `audit_logs(action='feature_flag.toggled', …)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.11).