# Omni Runner — SLO/SLI Operational Manual

> **Audit ref:** L20-02 — Sem SLO/SLI definidos → impossível ter alert policy razoável
> **Source of truth:** [`observability/slo.yaml`](../../observability/slo.yaml) (OpenSLO 1.0)

## Por que SLO?

Antes desta correção, alertas Sentry/Datadog usavam **thresholds absolutos
chutados** ("> 100 errors/min"). Isso quebra de duas formas:

1. **Falsos positivos**: 100 errors/min em horário de pico (50k req/min) é
   ruído (0.2% taxa de erro); fora do pico pode ser apocalipse.
2. **Falsos negativos**: 50 errors/min para `/api/custody/withdraw` (rota
   crítica) passa silenciosamente sob o threshold mas é incidente P1
   (cada erro = transação financeira potencialmente perdida).

SLO/SLI baseado em **taxa de sucesso** (não contagem absoluta) e **error
budget** (orçamento de falha permitido) resolve ambos: o alerta dispara
quando o **ritmo de queima do orçamento** indica que vamos esgotá-lo
antes do fim da janela.

## Catálogo de SLOs

Visão high-level — definição completa em `observability/slo.yaml`.

| SLO | Target | Window | Severity | Justificativa |
|---|---|---|---|---|
| `api_custody_deposit_availability` | 99.9% | 30d | P1 | Cada falha = depósito perdido / dupla cobrança risk |
| `api_custody_withdraw_availability` | 99.9% | 30d | P1 | Atleta sem dinheiro = trust-breaking |
| `api_custody_withdraw_latency_p99` | 95% < 500ms | 30d | P1 | UX direta no momento mais sensível |
| `api_swap_availability` | 99.9% | 30d | P1 | Coin↔BRL rail — core marketplace |
| `api_distribute_coins_availability` | 99.9% | 30d | P1 | Fan-out de prêmios — afeta múltiplos atletas |
| `webhook_processing_p99` | 99% < 30s | 7d | P1 | Asaas timeout aos 30s; perder evento = reconciliação manual |
| `custody_invariants_correctness` | 99.99% | 30d | P1 | Contabilidade — 1 violação ≠ degradação, é incidente |
| `api_sessions_upload_availability` | 99.5% | 30d | P2 | Treino sem upload é UX ruim mas dados não perdem (retry local) |
| `api_coaching_availability` | 99.5% | 30d | P2 | Convite/membership — afeta time, mas não financeiro |
| `api_auth_callback_availability` | 99.9% | 30d | P1 | Auth down = 100% impacto (ninguém loga) |
| `mobile_session_ingest_freshness` | 99% < 60s lag | 7d | P2 | Lente 21 — atleta de elite quer dado em tempo real |

## Burn-rate alerting (Google SRE workbook ch.5)

### Conceito
Multi-window multi-burn-rate alerting compara **taxa de queima atual**
(short window) e **sustentabilidade** (long window). Alerta dispara
SOMENTE se ambas as janelas indicarem queima excessiva — elimina spike
transient (long window não confirma) e degradação sustentada lenta
(short window confirma).

### Tabela de calibração

Para SLO de **99.9%** (error budget = 0.1% = 43m20s/30d):

| Burn rate | Significado | Short window | Long window | Severity | Notification |
|---|---|---|---|---|---|
| **14.4×** | Queima 2% do budget em 1h | 5m | 1h | P1 | Pager (PagerDuty) |
| **6×** | Queima 5% do budget em 6h | 30m | 6h | P1 | Pager |
| **3×** | Queima 10% do budget em 1d | 2h | 1d | P2 | Slack #incidents |
| **1×** | Queima 100% do budget em 30d | 6h | 3d | P3 | GitHub issue auto |

### Fórmula PromQL canônica

Para `api_custody_deposit_availability` (target 99.9%, error budget 0.1%):

```promql
# Short window: errors em últimos 5m / total em últimos 5m
( sum(rate(http_requests_total{route="/api/custody/deposit",status=~"5.."}[5m]))
  / sum(rate(http_requests_total{route="/api/custody/deposit"}[5m])) )
> (14.4 * (1 - 0.999))
AND
# Long window: errors em últimas 1h / total em última 1h
( sum(rate(http_requests_total{route="/api/custody/deposit",status=~"5.."}[1h]))
  / sum(rate(http_requests_total{route="/api/custody/deposit"}[1h])) )
> (14.4 * (1 - 0.999))
```

`14.4 × (1 - 0.999) = 0.0144` → alerta dispara quando taxa de erro >
1.44% sustentada em ambas janelas.

## Como adicionar/modificar um SLO

1. **Editar** `observability/slo.yaml` (seguir esquema OpenSLO 1.0).
2. **Justificar** target/window no campo `displayName` + comentário inline
   citando incidente ou requisito de negócio que motivou.
3. **PR review obrigatório**: SLO é contrato — modificá-lo depois de
   estabelecido pode esconder regressões.
4. **Atualizar** este `SLO.md` (tabela de catálogo).
5. **Sincronizar** com runbook downstream (`docs/runbooks/`) — todo SLO
   P1 precisa ter runbook associado para resposta a alerta.

## Ratchet policy

SLOs são **ratcheted-up** trimestralmente (sobem o target conforme
melhoramos), nunca rebaixados sem post-mortem. Se ficamos consistentemente
acima do target por 90 dias seguidos, próxima revisão SOBE o target em
um nível (e.g. 99.9% → 99.95%) — reduz error budget, força investimento
em qualidade adicional.

## Stack de implementação (deferido para Onda 1 phase 2)

Este YAML é a fonte canônica HOJE. Conforme Sentry/Datadog/Grafana
forem provisionados (ver `observability/README.md`), os adapters serão:

- **Sentry**: alertas custom usando query DSL — cobrir P1 SLOs primeiro.
- **Grafana**: dashboards consultando Prometheus / Datadog — ver
  `observability/grafana/dashboards/financial-ops.json` (L20-01).
- **Pyrra/Sloth**: gerar regras Prometheus a partir do YAML
  automaticamente. Comando exemplo:
  ```bash
  pyrra generate observability/slo.yaml > observability/prometheus-rules.yaml
  ```

## Histórico de revisões

| Data | Mudança | Razão |
|---|---|---|
| 2026-04-17 | Versão inicial (11 SLOs cobrindo P1+P2 críticos) | L20-02 fechado |
