---
id: L18-10
audit_ref: "18.10"
lens: 18
title: "Sem health-check de business logic (vs infra)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "webhook", "performance", "reliability"]
files: []
correction_type: process
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
# [L18-10] Sem health-check de business logic (vs infra)
> **Lente:** 18 — Principal Eng · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `/api/health` checa DB + invariants. Não checa:

- Latência média do RPC `execute_burn_atomic` nos últimos 5 min
- Taxa de falha de webhooks entrantes
- Backlog de `clearing_settlements` em `pending`
## Correção proposta

— Endpoint `/api/internal/business-health` com métricas:

```typescript
{
  rpc_latency_p99_ms: { execute_burn: 230, execute_swap: 180 },
  webhook_success_rate: { stripe: 0.999, mercadopago: 0.987, asaas: 0.95 },
  clearing_pending_count: 7,
  withdrawal_processing_count: 2,
  oldest_pending_deposit_hours: 0.3,
}
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.10).