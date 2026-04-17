---
id: L06-09
audit_ref: "6.9"
lens: 6
title: "Métricas (portal/src/lib/metrics.ts) só geram log JSON, sem exporter real"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["observability"]
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
# [L06-09] Métricas (portal/src/lib/metrics.ts) só geram log JSON, sem exporter real
> **Lente:** 6 — COO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `metrics.ts:LogMetricsCollector` registra via `logger.info`. Não há Prometheus/StatsD/Datadog na prática.
## Risco / Impacto

— Em produção os "metrics" são apenas linhas no Vercel logs — caros, não agregam, sem alerting.

## Correção proposta

— Trocar por `@opentelemetry/api-metrics` + exporter OTLP, apontar para Grafana Cloud ou Datadog. Ou, mínimo, criar `DatadogMetricsCollector` chamando `datadogRum.addTiming(...)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.9).