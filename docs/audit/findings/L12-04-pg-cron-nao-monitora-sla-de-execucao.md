---
id: L12-04
audit_ref: "12.4"
lens: 12
title: "pg_cron não monitora SLA de execução"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "migration", "cron", "reliability", "observability", "performance"]
files:
  - "supabase/migrations/20260420140000_l12_cron_sla_monitoring.sql"
  - "portal/src/lib/cron-sla.ts"
  - "portal/src/app/api/platform/cron-sla/route.ts"
  - "docs/runbooks/CRON_HEALTH_RUNBOOK.md"
  - "docs/runbooks/README.md"
correction_type: code
test_required: true
tests:
  - "tools/test_l12_04_cron_sla_monitor.ts"
  - "portal/src/lib/cron-sla.test.ts"
  - "portal/src/app/api/platform/cron-sla/route.test.ts"
linked_issues: []
linked_prs: ["685b769"]
owner: platform
runbook: docs/runbooks/CRON_HEALTH_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Solved with a five-layer pipeline that builds on top of the
  L12-03 cron_run_state substrate (no duplicate state) and the
  L06-04 alert-row pipeline (no duplicate ergonomics — SLA breaches
  flow into the SAME `cron_health_alerts` table, just tagged with
  `details.kind='sla_breach'` so the runbook can dispatch them
  separately):

    1. Append-only run-history ledger
       `public.cron_run_history` — captures every terminal
       transition (`completed | failed | timeout`) of
       `cron_run_state` via the `AFTER UPDATE` trigger
       `trg_cron_run_history_capture`. Includes
       `duration_seconds GENERATED ALWAYS AS STORED` so p50/p95/p99
       stop being a JOIN-and-extract chore. RLS forced + service-
       role only. Trigger is exception-swallowing so a buggy
       capture cannot block the host UPDATE that owns the lock.

    2. Per-job SLA thresholds table
       `public.cron_sla_thresholds (target_seconds, breach_seconds,
       enabled, notes)` — operator knob. Falls back to derived
       defaults (3× expected_interval) when a row is missing, so
       NO job goes unmonitored. CHECK enforces
       `breach_seconds >= target_seconds`. Seeded with explicit
       values for all 13 production jobs at migration time so the
       baseline ships tight, not "we'll tune it later".

    3. SLA stats aggregator
       `public.fn_compute_cron_sla_stats(p_window_hours int)` —
       STABLE SECURITY DEFINER, returns one row per known job
       with run_count, failed_count, avg/p50/p95/p99/max/last
       duration, breach_count, threshold source ('configured' |
       'derived'), and the resolved severity from the classifier.
       Rejects p_window_hours outside [1, 720] with SQLSTATE 22023.

    4. SLA classifier (mirrored SQL ↔ TS)
       `public.fn_classify_cron_sla(...)` IMMUTABLE — single source
       of truth for severity. The TS mirror at
       `portal/src/lib/cron-sla.ts::classifyCronSla` is
       byte-equivalent and locked down by 21 Vitest cases that
       hit every branch (disabled, zero runs, last-run breach,
       p95 breach, 2× breach upgrade, sustained avg drift). Any
       drift between the two implementations breaks the test.

    5. Scheduled wrapper
       `public.fn_alert_cron_sla_breaches_safe()` — wrapped in the
       L12-03 _safe pattern, scheduled `7,37 * * * *` (off-cycle
       from `cron-health-monitor` at `*/15`, so the two monitors
       don't fight). For each unhealthy row from (3) it calls
       `fn_record_cron_health_alert(name, severity,
       jsonb{kind:'sla_breach', ...}, cooldown_minutes:60)` from
       L06-04, RAISES NOTICE '[L12-04.sla] severity=... job=... ...'
       for the log aggregator, and prunes `cron_run_history` rows
       older than 30 days at the tail of every run.

    6. Admin endpoint
       `GET /api/platform/cron-sla?window_hours=N&severity_min=...`
       — auth-gated (platform_admins only), validates inputs with
       zod (window_hours ∈ [1, 720] int; severity_min ∈ enum),
       wraps the read-only RPC, ships counts-by-severity + the
       full job grid + threshold source + duration percentiles.
       Backed by gauge metrics (`cron_sla.total_jobs`,
       `cron_sla.unhealthy_jobs`, `cron_sla.critical_jobs`,
       `cron_sla.healthy`) so dashboards see the same numbers.

  Operator-facing decisions:
    • SLA monitoring is INDEPENDENT from health monitoring (L06-04).
      A job can be "scheduled correctly + firing on time" (L06-04
      green) and "running 12× longer than baseline" (L12-04 red)
      simultaneously. The runbook §2.5 spells out the distinction.
    • Adjusting a threshold is an INSERT...ON CONFLICT DO UPDATE
      on cron_sla_thresholds — no migration, no code change, no
      restart. Silencing during maintenance is `enabled=false`.
    • Existing alert dedup (L06-04 cooldown_minutes) is reused —
      same SRE muscle memory, same forensic queries, same dashboard.

  Runbook updates (`docs/runbooks/CRON_HEALTH_RUNBOOK.md`):
    • Trigger callout extended with L12-04 alert sources and the
      sla_breach details.kind discriminator.
    • Sintoma table: 4 new rows for SLA-specific signals.
    • New §2.5 — SLA view, severity table, threshold-tuning recipe.
    • New §3.8 — SLA breach diagnosis (spike vs drift vs silent
      failure), manual disarm, threshold-tightening guidance.
    • New §3.9 — cron-sla-monitor regression playbook + history
      retention force-prune.
    • §4 verification: queries 6 + 7 cover the L12-04 surface.
    • §6 references list extended with L12-04 migration, helper,
      endpoint, and integration test.

  Verification:
    • Migration self-test (in BEGIN/COMMIT) covers trigger fire/
      no-fire, idempotent UPDATE, classifier vectors, stats
      aggregator with synthetic history, and the alert pipeline
      end-to-end.
    • Integration tests (`tools/test_l12_04_cron_sla_monitor.ts`)
      add 19 black-box assertions including end-to-end "synthetic
      breaching job → alert row created with details.kind=sla_breach"
      and the schedule wiring + threshold seeding for cron-sla-
      monitor itself.
    • Vitest covers TS helper (21 tests) + admin endpoint (9 tests).
    • All tests pass: 30 vitest + 19 integration + 1 SQL self-test.
    • `npx tsc --noEmit` produces no NEW errors (only the
      pre-existing `lib/feature-flags.ts(69,22)` MapIterator note
      already documented in L06-04).
    • `npm run lint` clean for the L12-04 surface.

  Tracked progress: 97/348 fixed after this finding.
---
# [L12-04] pg_cron não monitora SLA de execução
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** Postgres + Portal admin

## Achado

Após L06-04 a plataforma sabe **se** um job rodou. Ela ainda não
sabe **quanto tempo** o job levou. Antes deste finding:

- `cron.job_run_details` registra `start_time`/`end_time`, mas não há
  retenção controlada, não há agregação, e nenhum dashboard
  consulta a tabela.
- `cron_run_state` (L12-03) sobrescreve a cada execução — perde
  a história necessária para p95/p99.
- Nenhum threshold por job — operador não consegue dizer "este
  cron deveria terminar em 60s, alerta se p95 passa de 240s"
  sem escrever query custom toda vez.
- Drifts silenciosos (RPC adicionado um JOIN sem índice, dataset
  cresceu sem partitioning) só são percebidos quando o job
  finalmente bate timeout (L02-10) ou rouba uma janela de outro
  job (L12-02 thundering herd).

## Risco / Impacto

`clearing-cron` historicamente fecha em 30s. Após uma migração
silenciosa de schema sem revisão de plano, passa a levar 8 min.
Por 6 semanas ninguém nota — está dentro da janela alocada (até
o próximo job às 03:00 UTC). Numa quarta-feira de pico (folha
de pagamento) começa a colidir com o `eval-verification-cron`,
ambos disputam locks, ambos timeout, ambos falham. Sem L12-04
o postmortem leva uma tarde para descobrir que a degradação é
de 6 semanas, não de 6 horas.

## Correção implementada

- `supabase/migrations/20260420140000_l12_cron_sla_monitoring.sql`
  — table `cron_run_history` (append-only, RLS forced), table
  `cron_sla_thresholds` (operator knob, RLS forced),
  trigger `trg_cron_run_history_capture`,
  classifier `fn_classify_cron_sla`,
  aggregator `fn_compute_cron_sla_stats`,
  wrapper `fn_alert_cron_sla_breaches_safe` agendado em `7,37 * * * *`,
  seed inicial de thresholds para os 13 jobs em produção +
  seed do próprio `cron-sla-monitor`.
- `portal/src/lib/cron-sla.ts` — espelho TS do classifier + helper
  `computeCronSlaStats` que normaliza a saída do RPC e expõe
  `countsBySeverity` para UI.
- `portal/src/app/api/platform/cron-sla/route.ts` — endpoint admin
  com filtros `window_hours` (1..720) + `severity_min` + métricas.
- `docs/runbooks/CRON_HEALTH_RUNBOOK.md` — §2.5 visão SLA,
  §3.8 SLA breach diagnosis, §3.9 cron-sla-monitor regressão,
  novas queries de verificação pós-mitigação (6 e 7).

## Referência narrativa

Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.4]`.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.4).
- `2026-04-21` — Corrigido (migration + helper + endpoint + runbook + 49 testes).
