---
id: L06-03
audit_ref: "6.3"
lens: 6
title: "reconcile-wallets-cron sem alerta em drift > 0"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-20
tags: ["finance", "atomicity", "webhook", "edge-function", "cron", "observability"]
files:
  - supabase/functions/reconcile-wallets-cron/index.ts
  - supabase/functions/_shared/wallet_drift.ts
  - supabase/migrations/20260420110000_l06_wallet_drift_events.sql
correction_type: process
test_required: true
tests:
  - supabase/functions/_shared/wallet_drift.test.ts
  - tools/test_l06_03_wallet_drift_events.ts
linked_issues: []
linked_prs: ["1efe8b6"]
owner: platform
runbook: docs/runbooks/WALLET_RECONCILIATION_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Defesa em 4 camadas: (1) `public.wallet_drift_events` (RLS-forced,
  service-role only) é a fonte forense definitiva — append-only, uma row
  por reconcile com `severity ∈ {warn, critical}`, persistida ANTES de
  qualquer tentativa de alerta externo (Slack/PagerDuty fora do ar não
  perde a trilha); (2) `fn_classify_wallet_drift_severity(count, threshold)`
  é IMMUTABLE e `fn_record_wallet_drift_event` + `fn_mark_wallet_drift_event_alerted`
  são SECURITY DEFINER + locked search_path + lock_timeout=2s; (3) helper
  Deno `_shared/wallet_drift.ts` mirror 1:1 da função SQL (`classifyWalletDrift`
  testado contra os mesmos vetores: 0/1/10/11/9999/NaN/Infinity/threshold
  customizado/threshold negativo); `buildSlackDriftPayload` emite Block
  Kit + plain-text fallback com tags P1/P2 alinhadas a
  `docs/observability/ALERT_POLICY.md` e `postSlackAlert` tem AbortController
  + 5s timeout (Slack outage NUNCA bloqueia o cron); (4) edge function
  `reconcile-wallets-cron/index.ts` reescrita para o pipeline completo:
  classifica → persiste → alerta → marca outcome → log estruturado com
  `severity: ALERT|CRITICAL` + `p_tier` como back-stop. Threshold default
  = 10 wallets (configurável via `WALLET_DRIFT_WARN_THRESHOLD`); webhook
  opcional via `WALLET_DRIFT_ALERT_WEBHOOK` (sem ela, a persistência
  continua + log captura). Verificação: 23/23 Deno tests para o helper
  (vetores de classificação, abort timeout, fetch throw captured), 14/14
  integration tests para SQL (table shape, CHECK enum, anon RLS-blocked,
  classify mirror, record/mark_alerted lifecycle, input validation 22023,
  índice partial), self-test in-TX da migration validou os 8 cenários
  internos. Audit verify 348/348. Runbook canônico
  `WALLET_RECONCILIATION_RUNBOOK.md` cobre 3 paths (drift detectado P2,
  drift CRITICAL P1 com kill-switches/dump CSV/postmortem, e pipeline de
  alerta quebrada com re-fire manual + tabela de erros típicos).
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
- `2026-04-20` — **Fix entregue.** Migration
  `20260420110000_l06_wallet_drift_events.sql` introduz tabela forense
  `wallet_drift_events` (RLS-forced, partial index `severity!='ok' AND
  alerted=false` para query "deveria ter sido alertado mas não foi") +
  funções `fn_classify_wallet_drift_severity` (IMMUTABLE, mirror byte-a-byte
  do helper Deno), `fn_record_wallet_drift_event` (SECURITY DEFINER,
  service-role only, persiste antes de qualquer alerta externo) e
  `fn_mark_wallet_drift_event_alerted` (registra outcome do Slack).
  Helper Deno `_shared/wallet_drift.ts` empacota classificação +
  Block-Kit Slack payload + delivery com 5s AbortController timeout.
  Edge function `reconcile-wallets-cron/index.ts` reescrita para o
  pipeline persist → alert → mark → log com severity tiers (warn = P2 /
  Slack, critical = P1 / page on-call), env vars opcionais
  `WALLET_DRIFT_WARN_THRESHOLD` (default 10), `WALLET_DRIFT_ALERT_WEBHOOK`,
  `WALLET_DRIFT_RUNBOOK_URL`, `ENVIRONMENT_LABEL`. Cobertura: 23 Deno +
  14 integration tests. Runbook canônico
  `docs/runbooks/WALLET_RECONCILIATION_RUNBOOK.md` cobre os 3 caminhos
  operacionais (P2, P1, pipeline de alerta quebrada).