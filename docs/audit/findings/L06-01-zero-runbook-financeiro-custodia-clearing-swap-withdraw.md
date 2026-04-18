---
id: L06-01
audit_ref: "6.1"
lens: 6
title: "Zero runbook financeiro — custódia, clearing, swap, withdraw"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "webhook", "migration", "observability", "reliability"]
files:
  - "docs/runbooks/README.md"
  - "docs/runbooks/CUSTODY_INCIDENT_RUNBOOK.md"
  - "docs/runbooks/CLEARING_STUCK_RUNBOOK.md"
  - "docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md"
  - "docs/runbooks/CHARGEBACK_RUNBOOK.md"
  - "docs/runbooks/GATEWAY_OUTAGE_RUNBOOK.md"
  - "docs/runbooks/WEBHOOK_BACKLOG_RUNBOOK.md"
correction_type: process
test_required: true
tests:
  - "docs/runbooks/README.md"
linked_issues: []
linked_prs:
  - "commit:c996831"
owner: unassigned
runbook: docs/runbooks/README.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Criados os 6 runbooks operacionais financeiros que faltavam, todos em
  `docs/runbooks/`:
  - **CUSTODY_INCIDENT_RUNBOOK** — invariant violations (SEV-0): kill
    switch, diagnóstico (4 SQL queries), 3 cenários de remediação
    (committed_negative, deposited_less_than_committed, committed_mismatch),
    validação e postmortem mandatório.
  - **CLEARING_STUCK_RUNBOOK** — settlements > 24h pending: 3 cenários
    (devedor com saldo, sem saldo, bug em settle), reuso de
    `clearing_failure_log` e métricas p50/p95.
  - **WITHDRAW_STUCK_RUNBOOK** — processing > 48h: 4 cenários (webhook
    perdido, provider processando, banco rejeitou, nunca chegou ao
    gateway), com SQL transacional para reverter saldo + estorno fx_spread.
  - **CHARGEBACK_RUNBOOK** — Asaas/Stripe dispute: contestar vs aceitar,
    burn de coins emitidas, registro de loss em platform_revenue, rate
    monitoring para evitar sanções do gateway (> 1%).
  - **GATEWAY_OUTAGE_RUNBOOK** — Asaas/Stripe down: kill switch, banner
    público, pause crons, drenagem pós-recovery, smoke test. Inclui
    referência rápida para status pages e API health endpoints.
  - **WEBHOOK_BACKLOG_RUNBOOK** — payment_webhook_events stuck: drenagem
    em batches com `FOR UPDATE SKIP LOCKED`, quarentena de duplicatas,
    replay individual.

  Cada runbook segue estrutura: trigger, diagnóstico (≤ 15min), remediação
  por cenário, validação, comunicação, postmortem. Referenciado pelo
  índice em `docs/runbooks/README.md` que classifica por severidade,
  trigger e tempo alvo. Cada runbook cita SQL real (function names,
  tabelas, colunas) baseado nas migrations atuais.

  Follow-ups identificados:
  - Tabela `feature_flags` (citada em vários runbooks) está pendente
    em **L06-06** — runbooks descrevem alternativa via env var Vercel
    enquanto isso.
  - Script `tools/replay-webhook-events.sh` mencionado no
    `WEBHOOK_BACKLOG_RUNBOOK#3.3` ainda precisa ser criado — backlog.
  - `docs/audit/runbooks/L01-17-asaas-vault-rotation.md` continua na
    pasta finding-specific (correto). Outros findings podem migrar
    para `docs/runbooks/` se virarem operacionais transversais.
  - Drills trimestrais documentados no README — primeiro ciclo deve
    rodar 2026-Q3.
---
# [L06-01] Zero runbook financeiro — custódia, clearing, swap, withdraw
> **Lente:** 6 — COO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `docs/` contém `ROLLBACK_RUNBOOK.md`, `OS06_RELEASE_RUNBOOK.md`, `WORKOUT_DELIVERY_RUNBOOK.md` mas **não existe**:

- `CUSTODY_INCIDENT_RUNBOOK.md` — o que fazer quando `check_custody_invariants()` retorna violações?
- `CLEARING_STUCK_RUNBOOK.md` — settlement em `pending` há 24 h
- `WITHDRAW_STUCK_RUNBOOK.md` — withdraw em `processing` há 48 h ([2.3])
- `CHARGEBACK_RUNBOOK.md` — Stripe abriu dispute, como reverter moedas emitidas? ([2.13])
- `GATEWAY_OUTAGE_RUNBOOK.md` — Asaas/Stripe/MP fora
- `WEBHOOK_BACKLOG_RUNBOOK.md` — fila de webhooks parada ([2.13])
## Risco / Impacto

— Operações financeiras dependem de decisões ad-hoc às 3 da manhã. Probabilidade muito alta de **decisão errada** durante incident → **perda financeira irreversível** em produto que lida com dinheiro real.

## Correção proposta

— Criar os 6 runbooks acima, cada um seguindo estrutura:

```markdown
# CUSTODY_INCIDENT_RUNBOOK

## Sintoma
- Dashboard: /api/health retorna status="degraded" com invariants.violations > 0
- Alertas Sentry: "check_custody_invariants violation detected"

## Diagnóstico (≤ 5 min)
1. SELECT * FROM check_custody_invariants();  -- lista violações
2. Identificar group_id afetado
3. SELECT * FROM custody_accounts WHERE group_id = X;
4. Comparar com SELECT SUM(delta_coins) FROM coin_ledger WHERE issuer_group_id = X;

## Remediação por tipo

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.1).
- `2026-04-17` — Criados os 6 runbooks operacionais financeiros em
  `docs/runbooks/` (CUSTODY_INCIDENT, CLEARING_STUCK, WITHDRAW_STUCK,
  CHARGEBACK, GATEWAY_OUTAGE, WEBHOOK_BACKLOG) + index README.
  Status → `fixed`.