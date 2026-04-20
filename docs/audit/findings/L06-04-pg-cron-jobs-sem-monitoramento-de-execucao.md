---
id: L06-04
audit_ref: "6.4"
lens: 6
title: "pg_cron jobs sem monitoramento de execução"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-20
tags: ["finance", "migration", "cron", "reliability", "observability"]
files:
  - "supabase/migrations/20260420130000_l06_cron_health_monitor.sql"
  - "portal/src/lib/cron-health.ts"
  - "portal/src/app/api/platform/cron-health/route.ts"
  - "docs/runbooks/CRON_HEALTH_RUNBOOK.md"
  - "docs/runbooks/README.md"
correction_type: code
test_required: true
tests:
  - "tools/test_l06_04_cron_health_monitor.ts"
  - "portal/src/lib/cron-health.test.ts"
  - "portal/src/app/api/platform/cron-health/route.test.ts"
linked_issues: []
linked_prs: ["0eb0317"]
owner: platform
runbook: docs/runbooks/CRON_HEALTH_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Solved with a four-layer pipeline that builds on the L12-03
  cron_run_state substrate (no duplicate state) and the L06-03
  alert-row pattern (no duplicate ergonomics):

    1. Read-only health view: `public.fn_check_cron_health()` UNIONs
       `cron.job` (scheduler-side truth) with `public.cron_run_state`
       (application-side truth), parses the cron expression to derive
       `expected_interval_seconds`, and emits a single severity enum
       per job (ok | warn | critical | unknown). Mirror in TS at
       `portal/src/lib/cron-health.ts::classifyCronSeverity` with
       byte-equivalent boundary tests. Severity is the same algorithm
       SQL- and TS-side: drifts of either implementation are caught
       by the integration test that exercises the SAME numeric vectors
       on both surfaces.

    2. Append-only dedup table `public.cron_health_alerts` —
       FORCE-RLS, service-role only, partial index on active rows.
       `fn_record_cron_health_alert(p_name, p_severity, p_details,
       p_cooldown_minutes)` does the dedup so a stuck job pages once
       per hour, not 4×/h. Severity upgrades (warn → critical) are
       NOT deduped — the page must fire.

    3. Scheduled wrapper `fn_alert_unhealthy_crons_safe` (every
       15 min, wrapped in the L12-03 _safe pattern) iterates the
       unhealthy rows from (1), calls (2) per offender, and
       RAISES NOTICE '[L06-04.alert] severity=... job=... ...' so
       the existing log aggregator picks each new alert up
       structurally.

    4. Admin endpoint `GET /api/platform/cron-health` — auth-gated
       (platform_admins only), wraps the read-only RPC, ships a
       counts-by-severity summary plus the full job grid. Backed by
       `gauge` metrics (`cron_health.total_jobs`,
       `cron_health.unhealthy_jobs`, `cron_health.critical_jobs`,
       `cron_health.healthy`) so the same data feeds dashboards.

  The runbook (CRON_HEALTH_RUNBOOK.md) was extended with §2.4
  (consolidated view), §3.6 (alert pipeline regression), §3.7
  (alert dedup forensics), and an additional verification query.

  Verification:
    • Migration self-test (in BEGIN/COMMIT) covers the 10
      cron-shape parser vectors, 9 severity classifier vectors,
      record-alert dedup, severity upgrade, and bad-input rejection.
    • Integration tests (`tools/test_l06_04_cron_health_monitor.ts`)
      add 19 black-box assertions including end-to-end "synthetic
      failed job → alert row created" and the schedule wiring.
    • Vitest covers TS helper (18 tests) + admin endpoint (7 tests).
    • All tests pass: 25 vitest + 19 integration + 1 SQL self-test.
    • `npx tsc --noEmit` produces no NEW errors (only the
      pre-existing `lib/feature-flags.ts(69,22)` MapIterator note).
    • `npm run lint` clean.

  Tracked progress: 64/179 fixed after this finding.
---
# [L06-04] pg_cron jobs sem monitoramento de execução
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-20)
**Camada:** Postgres + Portal admin

## Achado

`grep "cron.schedule" supabase/migrations/*.sql` lista 13 jobs em
produção (settle-clearing-batch, lifecycle-cron, expire-matchmaking-queue,
process-scheduled-workout-releases, reconcile-wallets-daily,
stale-withdrawals-alert, idempotency-keys-gc, eval-verification-cron,
archive-old-sessions, archive-old-ledger,
coin_ledger_ensure_partition_monthly, swap-expire,
auto-topup-hourly, onboarding-nudge-daily). Antes deste finding:

- Nenhuma view consolidada — `cron.job` × `cron_run_state` exigia
  JOIN manual a cada triagem.
- Nenhum classificador de "stale" relativo ao schedule esperado:
  um job `*/5` parado por 30 min é crítico; um partition pass de
  25 dias não é, e a triagem manual confundia os dois.
- Nenhum alerta automático quando um job some por > N ciclos;
  operadores só descobriam pela manifestação downstream
  (drift, backlog, reclamação de cliente).

## Risco / Impacto

`reconcile-wallets-daily` para silenciosamente; o alert pipeline
de L06-03 só dispara quando o reconcile detecta drift, não quando
ele não roda. Drift acumula 3 meses → auditoria revela US$ 50k
faltantes que poderiam ter sido caçados em < 24h.

## Correção implementada

- `supabase/migrations/20260420130000_l06_cron_health_monitor.sql`
  — table `cron_health_alerts`, parser `fn_parse_cron_interval_seconds`,
  classifier `fn_classify_cron_severity`, view `fn_check_cron_health`,
  recorder `fn_record_cron_health_alert`, wrapper
  `fn_alert_unhealthy_crons_safe` agendado em `*/15 * * * *`.
- `portal/src/lib/cron-health.ts` — espelho TS do classifier + helper
  `checkCronHealth` que normaliza a saída do RPC.
- `portal/src/app/api/platform/cron-health/route.ts` — endpoint admin
  com filtro `severity_min` + métricas Datadog.
- `docs/runbooks/CRON_HEALTH_RUNBOOK.md` — §2.4 visão consolidada,
  §3.6 alert pipeline regredido, §3.7 alert dedup, novas queries
  de verificação pós-mitigação.

## Referência narrativa

Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.4]`.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.4).
- `2026-04-20` — Corrigido (migration + helper + endpoint + runbook + 44 testes).
