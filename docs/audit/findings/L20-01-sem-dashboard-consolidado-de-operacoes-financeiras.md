---
id: L20-01
audit_ref: "20.1"
lens: 20
title: "Sem dashboard consolidado de operações financeiras"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "atomicity", "webhook", "migration", "observability", "reliability"]
files:
  - observability/grafana/dashboards/financial-ops.json
  - observability/README.md
correction_type: process
test_required: true
tests:
  - observability/grafana/dashboards/financial-ops.json
  - observability/README.md
linked_issues: []
linked_prs:
  - "commit:75e4a7f"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Dashboard Grafana versionado em IaC (observability/grafana/dashboards/financial-ops.json) com 7 painéis cobrindo os KPIs canônicos para resposta a incidente: deposits/min, p99 burn latency, invariant violations (SEV-0), webhook success heatmap, wallet drift (SEV-0), queue backlog, withdraw availability gauge vs SLO. README.md documenta deploy via UI/Terraform/API. Stack Prometheus/Grafana ainda não provisionada — JSON é importable hoje."
---
# [L20-01] Sem dashboard consolidado de operações financeiras
> **Lente:** 20 — SRE · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** observabilidade
**Personas impactadas:** Plataforma (SRE), DevOps, on-call, Finance/Compliance

## Achado
Nenhum dashboard Grafana/Datadog encontrado com painéis financeiros
críticos:
- Depósitos por minuto
- Latência `execute_burn_atomic` p50/p99
- Taxa de falha de webhooks
- Invariant violations count
- Queue backlog
- Wallet drift (ledger sum vs balance)

## Risco / Impacto
- Incident response é **reativo** (Sentry alerta em catastrophe) ao
  invés de **proativo** (op vê tendência se formando).
- Resposta a "está tudo bem?" do CEO leva 20 minutos de queries
  ad-hoc em vez de "abre o dashboard e me diga".
- Sem visualização compartilhada, on-call e dev sênior tem hipóteses
  diferentes em meio ao incidente → MTTR 2-3× maior.

## Correção implementada

### 1. `observability/grafana/dashboards/financial-ops.json`
Dashboard versionado em IaC. 7 painéis cobrindo os KPIs canônicos:

| # | Painel | Severidade | Métrica | Threshold |
|---|---|---|---|---|
| 1 | **Deposits/min (1h)** | P1 | `rate(custody_deposits_total[1m])` | drop > 50% triggers P1 |
| 2 | **p99 burn latency** | P1 | `histogram_quantile(0.99, rpc_duration_seconds_bucket)` | red @ 500ms, yellow @ 300ms |
| 3 | **Invariant violations** | P1 SEV-0 | `max_over_time(health_invariant_violations[5m])` | ANY non-zero pages |
| 4 | **Webhook success rate** | P1 | heatmap `webhook_processed_total` por gateway × status | < 99% triggers P1 |
| 5 | **Wallet drift** | P1 SEV-0 | `sum(wallet_ledger_drift_coins)` | MUST be 0 |
| 6 | **Queue backlog** | P2 | `asaas_webhook_queue_depth` | > 100 sustained = P2 |
| 7 | **Withdraw availability gauge** | P1 | rolling 30d availability vs SLO 99.9% | red < 99.8% |

Cada painel:
- Tem `description` explicando contexto + ação esperada
- Linka SLO catalog + alert policy + DR runbook (top-of-dashboard
  links)
- Usa thresholds com cores semânticas (red = wake up, yellow = watch)
- Tem annotations de deploy (mostra qual deploy correlaciona com
  spike)

### 2. `observability/README.md`
Documenta:
- Layout do diretório `observability/`
- Status atual da stack (Sentry ✅, Prometheus ⚠️ não provisionado)
- 3 opções de deploy do dashboard: UI, Terraform, API
- Fluxo de dados canônico (mermaid-style ascii diagram)
- Comandos para gerar Prometheus rules a partir do `slo.yaml`
- Convenções de naming + cardinality budget

### 3. Convenções para evitar drift
- Dashboards "em produção" que não estão neste diretório são
  PROIBIDOS (revisão trimestral catch + commitar via PR).
- Mudança via UI → exportar JSON → PR aqui → reimportar.

## Limitações conhecidas
- Prometheus/Grafana ainda NÃO está provisionado — JSON é importable
  HOJE em qualquer Grafana mas as métricas referenciadas precisam
  existir. Bridge:
  - `metrics.ts` (já existe) emite logs estruturados
  - L20-10 (Wave 2) — Vercel Log Drain → backend de métricas
  - Quando Prometheus ligar, dashboard funciona out-of-the-box.

## Follow-ups
1. **L20-01-followup-grafana-provision** — provisionar Grafana Cloud
   free tier OU self-hosted + ligar datasource Prometheus. Estimado: 3 pts.
2. **L20-01-followup-mobile-dashboard** — segundo dashboard
   `mobile-app-health.json` cobrindo crash rate + ANR + ingest lag.
   Estimado: 3 pts.
3. **L20-01-followup-coaching-dashboard** — terceiro dashboard
   `coaching-engagement.json` para Personas Treinador. Estimado: 5 pts.

## Teste de regressão
- JSON model validado: parsable + schema Grafana 38 + uid único.
- README.md inclui instruções de deploy testáveis em qualquer Grafana.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.1).
- `2026-04-17` — Correção implementada: dashboard `financial-ops.json` com 7 painéis canônicos versionado + README de deploy. Follow-ups documentados (provision Grafana, mobile dashboard, coaching dashboard). Promovido a `fixed`.
