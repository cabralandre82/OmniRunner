---
id: L06-09
audit_ref: "6.9"
lens: 6
title: "Métricas (portal/src/lib/metrics.ts) só geram log JSON, sem exporter real"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["observability", "platform"]
files:
  - docs/runbooks/METRICS_EXPORTER_DECISION.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: platform+observability
runbook: docs/runbooks/METRICS_EXPORTER_DECISION.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Decisão ratificada: **manter `LogMetricsCollector` por
  pelo menos 12 meses**. Tabela em
  `docs/runbooks/METRICS_EXPORTER_DECISION.md` mostra que cada
  necessidade real (latência por rota, error rate,
  custody/clearing drift, cron health, webhook rate, liveness/
  readiness, cost-per-MAU) já é coberta por
  Sentry+L18-10/L06-12/L06-04/L06-03/L20-11. Triggers para
  flip-to-Prometheus/OTLP definidos: multi-tenant white-label,
  MAU > 100k, segundo deployment target, > 4h/sem em Metabase
  dashboards, postmortem citando "não vimos na métrica" 2x/
  trimestre. Catalog companion `METRIC_CATALOG.md` planejado
  como follow-up não-blocking.
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