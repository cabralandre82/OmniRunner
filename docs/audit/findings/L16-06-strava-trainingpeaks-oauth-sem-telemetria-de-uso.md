---
id: L16-06
audit_ref: "16.6"
lens: 16
title: "Strava / TrainingPeaks OAuth sem telemetria de uso"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["webhook", "integration"]
files:
  - supabase/migrations/20260421530000_l16_06_integration_telemetry.sql
  - supabase/functions/_shared/integration_telemetry.ts
  - supabase/functions/strava-webhook/index.ts
  - supabase/functions/trainingpeaks-oauth/index.ts
  - supabase/functions/trainingpeaks-sync/index.ts
  - portal/src/app/api/platform/integrations/health/route.ts
  - tools/audit/check-integration-telemetry.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - local:cfc0a10
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Integration telemetry pipeline now backs every OAuth / webhook /
  sync surface for Strava + TrainingPeaks. `integration_events`
  captures provider, event_type, status, latency, and external_id
  in an append-only log with RLS (own-user + platform_admin read),
  partial indexes on errors, and 90-day retention. The writer is
  `fn_log_integration_event` (SECURITY DEFINER, service-role-only,
  input clamping); the dashboard aggregator
  `fn_integration_health_snapshot` returns per-provider totals,
  error_rate, p50/p95 latency, and by_event_type breakdown under
  platform_role='admin' (42501 otherwise). `fn_integration_connected_counts`
  complements with live connection counters (strava_connections +
  coaching_device_links where provider=trainingpeaks). Edge
  functions now import `_shared/integration_telemetry.ts` and
  emit events on webhook receipt, dedup, token refresh
  success/failure, OAuth callback success/error, session import,
  and sync push outcomes. Portal route
  `/api/platform/integrations/health` proxies both RPCs with zod
  query validation and admin-only gating. CI guard
  `npm run audit:integration-telemetry` enforces 61 invariants.
---
# [L16-06] Strava / TrainingPeaks OAuth sem telemetria de uso
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `strava-webhook`, `trainingpeaks-sync` existem. Sem dashboard interno de: "% de atletas conectados ao Strava", "eventos/dia", "erros de sync".
## Risco / Impacto

— Feature flagship ruim → churn sem diagnóstico.

## Correção proposta

— Event `integration.strava.session_imported` + dashboard `/platform/integrations`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.6).