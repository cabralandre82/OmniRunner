---
id: L20-01
audit_ref: "20.1"
lens: 20
title: "Sem dashboard consolidado de operações financeiras"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "webhook", "migration", "observability", "reliability"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L20-01] Sem dashboard consolidado de operações financeiras
> **Lente:** 20 — SRE · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Nenhum Grafana/Datadog dashboard encontrado com painéis:

- Depósitos por minuto
- Latência `execute_burn_atomic` p50/p99
- Taxa de falha de webhooks
- Invariant violations count
- Queue backlog
## Risco / Impacto

— Incident response é reativo (Sentry alerta) ao invés de proativo.

## Correção proposta

— Dashboard IaC em `observability/grafana/dashboards/financial-ops.json` (versionado no repo, deploy via Terraform/Grafana API).

Painéis mínimos:

1. **Depositos/min (last 1h)** - `custody_deposits.created_at` rate
2. **p99 burn latency** - duração do RPC
3. **Invariant violations** - contagem de `check_custody_invariants()`
4. **Webhook success rate** - matriz por gateway × status
5. **Wallet drift** - diff entre ledger sum e wallet balance

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.1).