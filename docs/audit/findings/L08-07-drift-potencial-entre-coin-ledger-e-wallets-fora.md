---
id: L08-07
audit_ref: "8.7"
lens: 8
title: "Drift potencial entre coin_ledger e wallets fora do horário do cron"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-20
tags: ["finance", "migration", "cron", "reliability", "observability"]
files:
  - supabase/migrations/20260420120000_l08_wallet_ledger_drift_check.sql
  - portal/src/lib/wallet-invariants.ts
  - portal/src/app/api/platform/invariants/route.ts
  - portal/src/app/api/platform/invariants/wallets/route.ts
correction_type: process
test_required: true
tests:
  - portal/src/lib/wallet-invariants.test.ts
  - portal/src/app/api/platform/invariants/route.test.ts
  - portal/src/app/api/platform/invariants/wallets/route.test.ts
  - tools/test_l08_07_wallet_ledger_drift_check.ts
linked_issues: []
linked_prs: ["176745d"]
owner: platform
runbook: docs/runbooks/WALLET_RECONCILIATION_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  L08-07 fechado em 4 camadas — observação real-time **read-only** que
  reusa a infra de alerta de L06-03. Solução completa:

  1. **Camada DB** (`supabase/migrations/20260420120000_l08_wallet_ledger_drift_check.sql`):
     - `public.fn_check_wallet_ledger_drift(p_max_users int=5000, p_recent_hours int=24)`:
       SECURITY DEFINER + locked search_path; `lock_timeout=2s` +
       `statement_timeout=10s` para garantir bounded execution.
       p_max_users ∈ [1, 100000], p_recent_hours ∈ [0, 720].
     - Sampling priority: wallets com atividade no `coin_ledger` nas
       últimas `p_recent_hours` aparecem PRIMEIRO (drift novo só pode
       ter formado ali); resto cai em deterministic user_id order.
     - Retorna `(user_id, balance_coins, ledger_sum, drift,
       last_reconciled_at_ms, recent_activity)`.
     - Self-test in-transaction: validação de input (22023), drift
       sintético detectado com magnitude correta, cleanup completo.

  2. **Camada TS helper** (`portal/src/lib/wallet-invariants.ts`):
     - `checkWalletLedgerDrift(opts)` — wrapper tipado, normaliza
       campos bigint (string→number) e last_reconciled_at_ms (null-safe).
     - `checkAndRecordWalletDrift({runId, ...})` — combina detecção +
       classificação (`fn_classify_wallet_drift_severity` de L06-03) +
       persistência (`fn_record_wallet_drift_event` de L06-03) →
       reusa o pipeline Slack/PagerDuty existente.

  3. **Camada de endpoint admin**:
     - `GET /api/platform/invariants` (composto):
       custody invariants + wallet_drift sample (cap 50) + drift_event_id.
       Falha do drift check NÃO mascara resultado de custody.
     - `GET /api/platform/invariants/wallets?max_users=&recent_hours=&warn_threshold=`
       (wallet-only, full rows, knobs validados via Zod com `.strict()`):
       endpoint dedicado para CSV-export durante triagem de incidente.
     - Métricas: `invariants.wallet_drift_count` (gauge),
       `invariants.wallet_drift_healthy` (0/1),
       `invariants.wallet_drift_check_ms` (timing),
       `invariants.wallet_drift_check_error` (counter).

  4. **Camada de documentação**:
     - `docs/runbooks/WALLET_RECONCILIATION_RUNBOOK.md` §3.0 reescrita:
       como rodar o check real-time pelos 3 caminhos (composto, dedicado,
       SQL direto), quando usar real-time vs. cron, exemplos de SQL para
       triagem (drift por activity status, ad-hoc full audit).

  Verificação:
  - `vitest run` — 55 tests passed (5 files, incluindo
    src/lib/wallet-invariants.test.ts: 11/11,
    src/app/api/platform/invariants/route.test.ts: 8/8,
    src/app/api/platform/invariants/wallets/route.test.ts: 8/8).
  - Integration test (`tools/test_l08_07_wallet_ledger_drift_check.ts`):
    8/8 passed — input validation, row shape, drift detection com
    magnitude, reconcile_wallet limpa drift de subsequent scans,
    p_max_users clampa working set.
  - Migration self-test passou (NOTICE "[L08-07] migration self-test
    PASSED") com cleanup de toda state sintética.
  - L06-03 integration test (`tools/test_l06_03_wallet_drift_events.ts`)
    continua passando (14/14) — pipeline de alerta L06-03 não regrediu.
  - `tools/audit/verify.ts` — 348 findings validados.
  - `tsc --noEmit` — zero novos erros nos arquivos criados (pre-existente
    `feature-flags.ts` MapIterator unrelated).

  Impacto:
  - Operadores agora detectam drift wallet↔ledger em segundos via
    `/api/platform/invariants` (antes: esperar até 24h pela próxima
    execução do reconcile-cron diário).
  - Ad-hoc detections fanout para o mesmo Slack channel que cron-detected
    drifts (via `wallet_drift_events` + `fn_record_wallet_drift_event` de
    L06-03), unificando alert pipeline.
  - Função é puramente read-only — não altera comportamento do cron
    diário; correção continua sob `reconcile_wallet`.
---
# [L08-07] Drift potencial entre coin_ledger e wallets fora do horário do cron
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `reconcile-wallets-cron` roda 1x/dia. Entre reconciliações, drift pode crescer invisível.
## Correção proposta

— Acrescentar check em `check_custody_invariants()`:

```sql
-- ... existing checks, plus:
UNION ALL
SELECT 'wallet_vs_ledger' AS invariant, w.user_id::text,
       jsonb_build_object('wallet', w.balance_coins, 'ledger', COALESCE(sum_delta, 0))
FROM wallets w
LEFT JOIN (
  SELECT user_id, SUM(delta_coins) AS sum_delta FROM coin_ledger GROUP BY user_id
) l ON w.user_id = l.user_id
WHERE w.balance_coins <> COALESCE(l.sum_delta, 0);
```

Health-check captura drift em tempo real (não só 1x/dia).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.7).
- `2026-04-20` — Corrigido. Em vez de extender `check_custody_invariants()`
  (que tem return shape incompatível com check user-keyed), a correção
  introduziu uma função dedicada `public.fn_check_wallet_ledger_drift`
  (bounded scan: `p_max_users ∈ [1, 100000]`, `p_recent_hours ∈ [0, 720]`,
  com `lock_timeout=2s` + `statement_timeout=10s`) e wirou o resultado em
  dois endpoints admin: `GET /api/platform/invariants` (composto, sample
  cap 50) e `GET /api/platform/invariants/wallets` (wallet-only, full
  rows + knobs). Detecções ad-hoc fanout no MESMO pipeline Slack de
  L06-03 via `wallet_drift_events` (severity classificada por
  `fn_classify_wallet_drift_severity`). Função é read-only (não auto-
  corrige) — correção continua a cargo de `reconcile_wallet`. Verificado
  com 55 vitest + 8 integration + migration self-test + 348 findings
  validados.
