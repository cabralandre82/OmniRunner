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
| [`ASAAS_WEBHOOK_RUNBOOK.md`](./ASAAS_WEBHOOK_RUNBOOK.md) | 401 spike no `asaas-webhook` OU DLQ provider=asaas crescendo (L01-18) | P1/P2 | 4 h drenagem |

### Privacidade / LGPD
| Runbook | Trigger | Severidade | Tempo alvo |
|---|---|---|---|
| [`ACCOUNT_DELETION_RUNBOOK.md`](./ACCOUNT_DELETION_RUNBOOK.md) | `account_deletion_log.outcome` em estado de falha (L04-02 / L01-36 / L06-08) OU reclamação ANPD | P1 (`auth_delete_failed`) / P2 (`cleanup_failed`) | resolução < 24 h |

### Cron / Scheduler (L12)
| Runbook | Trigger | Severidade | Tempo alvo |
|---|---|---|---|
| [`CRON_HEALTH_RUNBOOK.md`](./CRON_HEALTH_RUNBOOK.md) | Cron ausente, `last_status='failed'` por > 1 ciclo, `skip_count` crescendo, ou herd 03:00 UTC voltou (L12-01 / L12-02 / L12-03) | P1 (reconcile) / P2 (lifecycle/matchmaking/releases) / P3 (archive/partition) | ack < 1 h, mitig < 4 h |

### DBA / Storage (L19)
| Runbook | Trigger | Severidade | Tempo alvo |
|---|---|---|---|
| [`DBA_BLOAT_AND_INDEX_RUNBOOK.md`](./DBA_BLOAT_AND_INDEX_RUNBOOK.md) | Bloat > 30% em `coin_ledger`/`sessions`, archive cron falhando, novo índice redundante introduzido (L19-02 / L19-03) | P3 base; P2 se latência financeira p95 > 500ms; P1 se disk > 80% | ack < 4 h, mitig < 24 h |

### Idempotency / Wallet integrity (L18)
| Runbook | Trigger | Severidade | Tempo alvo |
|---|---|---|---|
| [`IDEMPOTENCY_RUNBOOK.md`](./IDEMPOTENCY_RUNBOOK.md) | Duplicate-mutation report, `idempotency-keys-gc` cron failing, `idempotency_keys` > 1M rows, `409 IDEMPOTENCY_KEY_CONFLICT` rate spike (L18-02) | P2 (gc backlog / 409 spike); P1 (confirmed duplicate financial mutation) | ack < 1 h, mitig < 4 h |
| [`WALLET_MUTATION_GUARD_RUNBOOK.md`](./WALLET_MUTATION_GUARD_RUNBOOK.md) | New RPC blocked by `WALLET_MUTATION_FORBIDDEN` (P0007), wallet drift alert (`balance_coins ≠ SUM(coin_ledger)`), or onboarding a new credit/debit code-path (L18-01) | P2 (CI block / new-code question); P1 (confirmed drift in production) | ack < 1 h, mitig < 4 h |
| [`FEATURE_FLAGS_RUNBOOK.md`](./FEATURE_FLAGS_RUNBOOK.md) | Kill switch toggle slow to propagate (> 5s), A/B experiment shows lopsided populations after L18-07 deploy, `feature_flags` DB load spike, or onboarding a new kill switch / A/B flag (L18-06 / L18-07) | P3 (recategorisation / A/B audit); P2 (sustained slow propagation) | ack < 4 h, mitig < 24 h |

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
