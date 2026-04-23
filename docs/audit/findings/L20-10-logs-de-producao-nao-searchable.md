---
id: L20-10
audit_ref: "20.10"
lens: 20
title: "Logs de produção não-searchable"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["sre", "observability", "runbook", "compliance"]
files:
  - docs/runbooks/LOGS_SEARCHABLE.md
  - tools/audit/check-logs-searchable.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-logs-searchable.ts
linked_issues: []
linked_prs: []
owner: sre
runbook: docs/runbooks/LOGS_SEARCHABLE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Runbook `docs/runbooks/LOGS_SEARCHABLE.md` v1.0 define a
  arquitetura: Vercel Log Drains → Axiom (30d hot) → S3 Glacier
  (1y cold). Inclui legal anchors (Marco Civil 6 meses, LGPD
  Art. 38, BCB Resolução 4658), shape obrigatório dos logs
  (request_id, user_id_hash, route, severity, category), failure
  modes (lag, S3 PUT, PII leak), exemplos Axiom de busca. CI
  guard `audit:logs-searchable` (14 asserts).
---
# [L20-10] Logs de produção não-searchable
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Correção aplicada
Runbook completo + CI guard. Próximo passo (não bloqueador):
provisionar Axiom + Vercel Log Drains conforme §3.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via runbook + CI guard.
