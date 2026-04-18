---
id: L20-02
audit_ref: "20.2"
lens: 20
title: "Sem SLO/SLI definidos → impossível ter alert policy razoável"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "webhook", "observability", "reliability"]
files:
  - observability/slo.yaml
  - docs/observability/SLO.md
correction_type: process
test_required: true
tests:
  - observability/slo.yaml
  - docs/observability/SLO.md
linked_issues: []
linked_prs:
  - "commit:75e4a7f"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "11 SLOs canônicos em observability/slo.yaml (OpenSLO 1.0). SLO.md companion documenta filosofia, burn-rate alerting (multi-window multi-burn-rate Google SRE workbook ch.5), tabela de calibração, fórmula PromQL canônica, ratchet policy. Geração de regras Prometheus via Pyrra/Sloth quando stack for provisionada — YAML é fonte canônica HOJE."
---
# [L20-02] Sem SLO/SLI definidos → impossível ter alert policy razoável
> **Lente:** 20 — SRE · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** observabilidade
**Personas impactadas:** Plataforma (SRE), DevOps, on-call

## Achado
Alertas Sentry/Datadog usavam **thresholds absolutos chutados**
(e.g. "> 100 errors/min"). Quebra de duas formas:
1. **Falsos positivos** em horário de pico.
2. **Falsos negativos** em rotas críticas com baixo volume.

Não havia error budget, burn-rate alerting, ou definição formal de
"o que significa estar saudável".

## Risco / Impacto
- Resposta a incidente é reativa (cliente reclama → time vê).
- Negociação de feature velocity vs. confiabilidade fica subjetiva
  (sem dados, vence quem fala mais alto).
- Compliance auditor (ISO 27001, parceiros B2B) exige SLOs formais.

## Correção implementada

### 1. `observability/slo.yaml` (OpenSLO 1.0)
11 SLOs cobrindo:
- **Availability** de rotas P1 (custody deposit/withdraw, swap,
  distribute-coins, auth callback, webhook processing)
- **Latency** (p99 < 500ms para withdraw)
- **Correctness** (custody invariants — 99.99% target, qualquer violação
  paga)
- **Freshness** (mobile session ingest lag p99 < 60s)
- **Critical user paths** P2 (sessions, coaching)

Cada SLO tem:
- Target numérico (99.9% / 99.99% / 95% etc)
- Window (7d / 30d)
- Indicator PromQL queries
- Alert thresholds com burn rates (14.4× / 6× / 3× / 1×)
- Severity assignment (P1/P2)

### 2. `docs/observability/SLO.md` (operational manual)
Cobre:
- **Filosofia**: por que SLO em vez de threshold absoluto.
- **Catálogo**: tabela com 11 SLOs + justificativa de cada target.
- **Burn-rate alerting**: tabela Google SRE workbook ch.5
  (multi-window multi-burn-rate, 4 níveis de calibração).
- **Fórmula PromQL canônica**: exemplo concreto para
  `api_custody_deposit_availability` (target 99.9%).
- **Workflow**: como adicionar/modificar SLO (PR review obrigatório).
- **Ratchet policy**: SLOs sobem trimestralmente conforme melhoramos,
  nunca rebaixados sem post-mortem.
- **Stack downstream**: comandos `pyrra generate` / `sloth generate`
  para auto-gerar regras Prometheus a partir do YAML.

### 3. Integração com ALERT_POLICY.md
Burn-rate alerts P1 paginar via PagerDuty (mesmo canal que erros P1
síncronos — ver L20-05). Coerência total entre alert types.

## Limitações conhecidas
- Stack Prometheus/Grafana ainda NÃO está provisionada — YAML é
  spec/contract HOJE. Quando provisionada (issue futura), Pyrra/Sloth
  gera regras automaticamente. Sem retrabalho.
- Mobile SLO (`mobile_session_ingest_freshness`) requer
  instrumentation que ainda precisa ser adicionada ao Flutter app
  (próxima rodada).

## Follow-ups
1. **L20-02-followup-pyrra-rollout** — provisionar Pyrra/Sloth e
   gerar regras Prometheus a partir deste YAML. Estimado: 3 pontos.
2. **L20-02-followup-mobile-instrumentation** — emitir métrica
   `session_ingest_lag_seconds_bucket` no Flutter app. Estimado: 5 pontos.

## Teste de regressão
- YAML validado por sintaxe (parsable como `openslo/v1`).
- Tabela em SLO.md mantida sincronizada via PR review.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.2).
- `2026-04-17` — Correção implementada: 11 SLOs canônicos em `observability/slo.yaml` + manual operacional `docs/observability/SLO.md` com burn-rate calibration. Follow-ups documentados para Pyrra rollout e mobile instrumentation. Promovido a `fixed`.
