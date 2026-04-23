# Service-Role Key Usage Inventory

**Finding:** [L10-03](../audit/findings/L10-03-service-role-key-distribuida-amplamente.md)
**Runbook:** [docs/runbooks/SERVICE_ROLE_ROTATION_RUNBOOK.md](../runbooks/SERVICE_ROLE_ROTATION_RUNBOOK.md)
**Guard:** `npm run audit:service-role-inventory`

This file is the canonical allowlist of every file in the repo that is allowed to reference `SUPABASE_SERVICE_ROLE_KEY` (or its `_STAGING` / `_PREVIEW` / `_CI` variants). A CI guard greps the repo and fails the build if a new consumer appears outside this list. That friction is intentional — the service role bypasses every RLS policy on the platform and every new consumer deserves explicit security review.

## Environment variants

| Name                                  | Intended environment |
| ------------------------------------- | -------------------- |
| `SUPABASE_SERVICE_ROLE_KEY`           | production runtime   |
| `SUPABASE_SERVICE_ROLE_KEY_STAGING`   | staging runtime      |
| `SUPABASE_SERVICE_ROLE_KEY_PREVIEW`   | PR preview deploys   |
| `SUPABASE_SERVICE_ROLE_KEY_CI`        | CI E2E / k6 jobs     |

Production key must never be available in preview, CI, or staging. Infra pins this via separate Supabase projects per env.

## Expected consumers

### 1. Portal (Next.js)

| File | Purpose |
|------|---------|
| `portal/src/lib/supabase/service.ts` | Canonical server-side service-role client factory. All API routes import from here. |
| `portal/src/lib/supabase/admin.ts` | Admin-only client wrapper (platform_admin ops). |
| `portal/src/app/api/platform/liga/route.ts` | Liga snapshot job that needs RLS bypass for cross-group aggregates. |

### 2. Supabase Edge Functions

| File | Purpose |
|------|---------|
| `supabase/functions/_shared/auth.ts` | `requireUser` helper — creates the service-role client used by every function. |
| `supabase/functions/_shared/feature_flags.ts` | Service-role read of platform feature flags. |
| `supabase/functions/archive-old-sessions/index.ts` | Cron: archive inactive sessions. |
| `supabase/functions/asaas-webhook/index.ts` | Payment webhook ingestion. |
| `supabase/functions/auto-topup-check/index.ts` | Daily-cap auto top-up evaluation. |
| `supabase/functions/auto-topup-cron/index.ts` | Auto top-up scheduler. |
| `supabase/functions/billing-reconcile/index.ts` | Nightly billing reconciliation. |
| `supabase/functions/challenge-invite-group/index.ts` | Group challenge invite fan-out. |
| `supabase/functions/challenge-join/index.ts` | Challenge join RPC. |
| `supabase/functions/challenge-withdraw/index.ts` | Challenge withdraw RPC. |
| `supabase/functions/champ-invite/index.ts` | Championship invite issuance. |
| `supabase/functions/evaluate-badges/index.ts` | Badge evaluation job. |
| `supabase/functions/eval-verification-cron/index.ts` | Nightly anti-cheat verification. |
| `supabase/functions/league-snapshot/index.ts` | League-level snapshot cron. |
| `supabase/functions/lifecycle-cron/index.ts` | User lifecycle transitions. |
| `supabase/functions/notify-rules/index.ts` | Notification rules engine. |
| `supabase/functions/onboarding-nudge/index.ts` | Onboarding nudge cron. |
| `supabase/functions/process-refund/index.ts` | Refund processor. |
| `supabase/functions/reconcile-wallets-cron/index.ts` | Wallet-ledger drift reconciliation. |
| `supabase/functions/release-scheduled-workouts/index.ts` | Scheduled workout release cron. |
| `supabase/functions/send-email/index.ts` | Transactional email sender. |
| `supabase/functions/send-push/index.ts` | Push notification sender. |
| `supabase/functions/settle-challenge/index.ts` | Challenge settlement RPC. |
| `supabase/functions/strava-register-webhook/index.ts` | Strava webhook registration. |
| `supabase/functions/strava-webhook/index.ts` | Strava activity ingest. |
| `supabase/functions/trainingpeaks-oauth/index.ts` | TrainingPeaks OAuth callback. |
| `supabase/functions/trainingpeaks-sync/index.ts` | TrainingPeaks sync worker. |
| `supabase/functions/webhook-mercadopago/index.ts` | Mercado Pago webhook. |
| `supabase/functions/webhook-payments/index.ts` | Generic payments webhook. |

### 3. CI / tooling (non-production key)

These files use the staging or CI key variant only. Production key must never be injected into any of them.

| File | Purpose |
|------|---------|
| `.github/workflows/portal.yml` | Portal E2E + k6 jobs. |
| `.github/workflows/supabase.yml` | Edge-function deploy + schema-drift checks. |
| `.github/workflows/update-snapshots.yml` | Storybook / metrics snapshot refresh. |
| `tools/audit/check-email-platform.ts` | Audit-on-main email platform invariants. |
| `tools/integration_tests.ts` | Cross-service integration test harness. |
| `tools/perf_seed.ts` | Performance test seed. |
| `tools/smoke_test_billing.sh` | Billing smoke test. |
| `tools/test_cron_health.ts` | Cron health verifier. |
| `tools/test_l02_10_clearing_settle_chunked.ts` | L02-10 regression test. |
| `tools/test_l02_realtime_rls_guard.ts` | Realtime RLS guard regression. |
| `tools/test_l03_02_freeze_clearing_fee.ts` | L03-02 regression test. |
| `tools/test_l03_03_provider_fee_revenue_track.ts` | L03-03 regression test. |
| `tools/test_l03_13_reverse_coins.ts` | L03-13 regression test. |
| `tools/test_l03_20_dispute_chargeback.ts` | L03-20 regression test. |
| `tools/test_l05_03_distribute_coins_batch.ts` | L05-03 regression test. |
| `tools/test_l05_09_custody_daily_cap.ts` | L05-09 regression test. |
| `tools/test_l06_03_wallet_drift_events.ts` | L06-03 regression test. |
| `tools/test_l06_04_cron_health_monitor.ts` | L06-04 regression test. |
| `tools/test_l08_01_02_product_events_hardening.ts` | L08-01/02 regression test. |
| `tools/test_l08_07_wallet_ledger_drift_check.ts` | L08-07 regression test. |
| `tools/test_l09_09_legal_contracts.ts` | L09-09 regression test. |
| `tools/test_l12_04_cron_sla_monitor.ts` | L12-04 regression test. |
| `tools/test_l12_05_auto_topup_daily_cap.ts` | L12-05 regression test. |
| `tools/test_l18_idempotency.ts` | L18-01 idempotency regression. |
| `tools/test_l18_wallet_guard.ts` | L18-01 wallet-guard regression. |
| `tools/test_l19_dba_health.ts` | L19 DBA health regression. |
| `tools/test_l21_01_02_anti_cheat_profile.ts` | L21-01/02 regression test. |
| `tools/verify_metrics_snapshots.ts` | Metrics snapshot verifier. |

## Adding a new consumer

1. Open a PR that updates this file first (in the same commit or a precursor commit).
2. Tag `@security` for explicit approval.
3. Document *why* the service role is needed instead of a narrower role. Consider `billing_role`, `platform_admin_role`, or a SECURITY DEFINER RPC instead.
4. The CI guard will now let the new consumer land.

## Rotation

See [SERVICE_ROLE_ROTATION_RUNBOOK](../runbooks/SERVICE_ROLE_ROTATION_RUNBOOK.md) for the quarterly + ad-hoc rotation procedure. Every consumer in this inventory is expected to pick up the new key on the next deploy / cron run.
