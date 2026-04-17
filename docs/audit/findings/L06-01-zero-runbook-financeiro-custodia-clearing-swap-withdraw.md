---
id: L06-01
audit_ref: "6.1"
lens: 6
title: "Zero runbook financeiro — custódia, clearing, swap, withdraw"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "migration", "observability", "reliability"]
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