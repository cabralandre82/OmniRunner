# Observability — Infrastructure as Code

> Audit refs: **L20-01** (dashboards) · **L20-02** (SLO/SLI) · **L20-04**+**L20-05** (Sentry tuning).

## Layout

```
observability/
├── README.md                          ← este arquivo
├── slo.yaml                           ← SLO/SLI canônicos (L20-02, OpenSLO 1.0)
└── grafana/
    └── dashboards/
        └── financial-ops.json         ← Dashboard de operações financeiras (L20-01)
```

Tudo aqui é **versionado e reviewable**. Não há "dashboard em produção"
que não esteja neste diretório — qualquer mudança feita direto na UI
deve ser exportada e commitada via PR.

## Status atual da stack

| Componente | Estado | Próximo passo |
|---|---|---|
| Sentry (errors + traces) | ✅ provisionado, configurado com `tracesSampler` adaptativo + severity tags (L20-04, L20-05) | Configurar alert rules consumindo `severity` tag (ver `docs/observability/ALERT_POLICY.md`) |
| SLO/SLI definitions | ✅ versionado (`slo.yaml`) | Provisionar Pyrra/Sloth para gerar regras Prometheus a partir do YAML |
| Grafana | ⚠️ não provisionado | Provisionar Grafana Cloud (free tier 10k series) ou self-hosted |
| Prometheus / metrics backend | ⚠️ não provisionado | Avaliar: Grafana Cloud Prometheus, Datadog Metrics, ou Mimir self-hosted |
| Log aggregation (>30d retention) | ⚠️ Vercel logs (3d) + Sentry breadcrumbs only | L20-10 (Wave 2) — Vercel Log Drain → Axiom/Datadog Logs |
| OpenTelemetry tracing | ⚠️ Sentry built-in tracing only | L20-03 (Wave 1 phase 2) — OTel SDK + OTLP exporter |
| Status page público | ⚠️ inexistente | L20-06 (Wave 1 phase 2) — Better Stack ou self-hosted |

## Como deployar o dashboard `financial-ops.json`

### Opção 1 — Grafana UI (one-shot)
1. Abrir Grafana → "Dashboards" → "Import".
2. Upload do arquivo `grafana/dashboards/financial-ops.json` OU paste do
   conteúdo na text area.
3. Selecionar datasource Prometheus quando solicitado.
4. Click "Import".

### Opção 2 — Terraform (recomendado para multi-env)
```hcl
resource "grafana_dashboard" "financial_ops" {
  config_json = file("${path.module}/observability/grafana/dashboards/financial-ops.json")
}
```

### Opção 3 — Grafana API (CI deploy)
```bash
curl -X POST https://grafana.example.com/api/dashboards/db \
  -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @observability/grafana/dashboards/financial-ops.json
```

### Painéis cobertos
1. **Deposits/min** (custody_deposits rate) — P1
2. **p99 burn latency** (execute_burn_atomic RPC) — P1
3. **Invariant violations** (check_custody_invariants) — P1 SEV-0
4. **Webhook success rate** (heatmap por gateway × status) — P1
5. **Wallet drift** (ledger sum − wallet balance — MUST be 0) — P1 SEV-0
6. **Queue backlog** (Asaas webhook reprocessing) — P2
7. **Withdraw availability gauge** (rolling 30d vs SLO 99.9%) — P1

## Fluxo de dados (canônico)

```
                  ┌─────────────────────────┐
                  │   portal/src/lib/       │
                  │   metrics.ts (logger)   │ ← já existe
                  │   ── ÚNICO ESCRITOR ──  │
                  └────────────┬────────────┘
                               │ structured JSON logs
                               ▼
       ┌───────────────────────────────────────────┐
       │    Vercel Logs → Log Drain (futuro)       │  L20-10
       │              ┌──────────┴──────────┐       │
       │       Axiom / Datadog       Prometheus    │  L20-01 deps
       │       (logs + search)       (metrics)     │
       └─────────────────┬─────────────────────────┘
                         │
                         ▼
                   Grafana dashboards (financial-ops.json)
                         │
                         ▼
                   Sentry alerts (severity-routed) ── PagerDuty/Slack
```

## Aplicar SLOs como Prometheus alert rules

Quando Prometheus estiver provisionado, gerar regras a partir do YAML:

```bash
# Pyrra (https://github.com/pyrra-dev/pyrra)
pyrra generate observability/slo.yaml > observability/prometheus-rules.yaml

# OU Sloth (https://sloth.dev)
sloth generate -i observability/slo.yaml -o observability/prometheus-rules.yaml
```

Submeter `prometheus-rules.yaml` ao Prometheus via ConfigMap (k8s) ou
via reload signal (bare-metal). O burn-rate alerting fica automático
para todos os 11 SLOs definidos.

## Convenções

- **Nome de métrica**: `<surface>_<entity>_<unit>` (ex. `custody_deposits_total`,
  `http_request_duration_seconds`).
- **Tags obrigatórias** em todo evento HTTP: `route`, `status`, `method`.
- **Tags obrigatórias** em métricas financeiras: `currency`, `gateway`,
  `result` (success/error/retry).
- **Cardinality budget**: máximo 10 valores únicos por tag por métrica.
  `user_id` → NUNCA em tag (use `user_segment` se precisar agrupar).
