---
id: L20-10
audit_ref: "20.10"
lens: 20
title: "Logs de produção não-searchable"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "observability", "reliability"]
files: []
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L20-10] Logs de produção não-searchable
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Logs vão para Vercel Functions logs (3 dias retention) + Sentry. Não há Loki/CloudWatch/Datadog Logs com retention > 30 dias.
## Correção proposta

— Vercel Log Drains → Datadog ou Axiom. Retention 30 dias para compliance, 1 ano para financeiros.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.10).