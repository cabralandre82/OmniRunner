---
id: L06-03
audit_ref: "6.3"
lens: 6
title: "reconcile-wallets-cron sem alerta em drift > 0"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "webhook", "edge-function", "cron", "observability"]
files:
  - supabase/functions/reconcile-wallets-cron/index.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L06-03] reconcile-wallets-cron sem alerta em drift > 0
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/reconcile-wallets-cron/index.ts` corrige drift e loga. Não há alerta se drift > 0, apenas log `console.error` que exige monitor externo já configurado. Até hoje o `docs/` não indica que esse log esteja conectado a Datadog/PagerDuty.
## Risco / Impacto

— Drift = indicador #1 de bug na RPC `execute_burn_atomic` ou corrupção; passa despercebido.

## Correção proposta

—

```typescript
if (wallets_corrected > 0) {
  await fetch(Deno.env.get("SLACK_ALERT_WEBHOOK")!, {
    method: "POST",
    body: JSON.stringify({
      text: `:rotating_light: Wallet drift detected: ${wallets_corrected} wallets corrected. ` +
            `Investigate execute_burn_atomic / fn_increment_wallets_batch.`,
    }),
  });
  // Also bump Sentry alert
}
```

Mais: se `wallets_corrected > threshold` (ex.: > 10), **abortar** a correção e criar incident, porque pode indicar bug sistêmico.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.3).