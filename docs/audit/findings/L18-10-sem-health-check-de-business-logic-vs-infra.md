---
id: L18-10
audit_ref: "18.10"
lens: 18
title: "Sem health-check de business logic (vs infra)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "webhook", "performance", "reliability"]
files:
  - portal/src/app/api/internal/business-health/route.ts
  - supabase/migrations/20260421850000_l18_10_business_health.sql
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 3af9c9b
  - 6285bdc
  - 01674b0
owner: platform-sre
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  /api/internal/business-health is admin-only and surfaces:
  rpc_latency_ms (p50/p95/p99 from pg_stat_statements via the new
  fn_rpc_latency_summary RPC for execute_burn_atomic +
  execute_swap_atomic + custody_commit_coins), webhook_success_rate
  (5-min rolling per provider), clearing_pending count + oldest age,
  withdrawal_pending, and oldest_pending_deposit. Each indicator
  errors independently (degraded:true + errors[] in the response)
  so partial outages still surface useful data on the SRE dashboard.
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