# docs/runbooks/ — Operational runbooks

> Runbooks **operacionais transversais** (incident response). Para runbooks
> ligados a um finding específico, ver `docs/audit/runbooks/`. Para
> runbooks legados (release / rollback / workout delivery), ver `docs/`.

## Catálogo

### Disaster recovery
| Runbook | Trigger | Severidade | Linked finding |
|---|---|---|---|
| [`DR_PROCEDURE.md`](./DR_PROCEDURE.md) | Drill quarterly OU corruption/loss real | P0 (drill), SEV-0 (real) | L20-07 |

### Operações financeiras (L06-01)
| Runbook | Trigger | Severidade | Tempo alvo |
|---|---|---|---|
| [`CUSTODY_INCIDENT_RUNBOOK.md`](./CUSTODY_INCIDENT_RUNBOOK.md) | `check_custody_invariants()` retorna ≥ 1 violação | SEV-0 (P1 page) | 30 min mitigation |
| [`CLEARING_STUCK_RUNBOOK.md`](./CLEARING_STUCK_RUNBOOK.md) | `clearing_settlements.status='pending'` há > 24h | P1 | 2 h |
| [`WITHDRAW_STUCK_RUNBOOK.md`](./WITHDRAW_STUCK_RUNBOOK.md) | `custody_withdrawals.status='processing'` há > 48h | P1 | 4 h |
| [`CHARGEBACK_RUNBOOK.md`](./CHARGEBACK_RUNBOOK.md) | Asaas/Stripe abre dispute em depósito já creditado | P1 | 24 h (prazo legal Asaas: 7 dias) |
| [`GATEWAY_OUTAGE_RUNBOOK.md`](./GATEWAY_OUTAGE_RUNBOOK.md) | Asaas/Stripe API down OU error rate > 50% por 5min | P1 | 15 min mitigation |
| [`WEBHOOK_BACKLOG_RUNBOOK.md`](./WEBHOOK_BACKLOG_RUNBOOK.md) | `payment_webhook_events.processed=false` count > 100 sustained 10min | P1 | 1 h |

## Convenções

- **Nome**: `<DOMÍNIO>_<NATUREZA>_RUNBOOK.md` (UPPERCASE para destaque vs.
  finding-specific kebab-case em `docs/audit/runbooks/`).
- **Estrutura mínima**: ver `docs/audit/runbooks/README.md` (template).
  Adapter livremente — runbook útil > runbook bonito.
- **Atualização**: depois de cada incidente real, dev de plantão tem 24h
  para atualizar o runbook usado (action item automático no postmortem).

## Severidade ladder
Ver `docs/observability/ALERT_POLICY.md` para tabela completa.
- **SEV-0 / P1** → PagerDuty page → wake on-call
- **P2** → Slack `#incidents` (no pager)
- **P3** → Daily digest

## Como adicionar um novo runbook

1. Criar arquivo `docs/runbooks/<NOME>.md` seguindo template em
   `docs/audit/runbooks/README.md`.
2. Atualizar este index.
3. Adicionar `runbook: docs/runbooks/<nome>.md` no frontmatter de
   findings relacionados.
4. PR review por platform team.

## Drills

Trimestralmente, escolher 1-2 runbooks deste catálogo e rodar drill em
staging:
- Forçar a condição (e.g. seed `payment_webhook_events.processed=false`
  com 200 rows).
- On-call tenta seguir o runbook sem ajuda externa.
- Cronometrar tempo até mitigation.
- Atualizar runbook se algum passo foi ambíguo OU faltou.
- Postar resumo em `#platform-ops`.
