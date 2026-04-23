---
id: L04-09
audit_ref: "4.9"
lens: 4
title: "Terceiros (Strava, TrainingPeaks) — não há processo de revogação"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["lgpd", "webhook", "security-headers", "integration", "mobile", "cron"]
files:
  - supabase/migrations/20260421420000_l04_09_third_party_revocation.sql
  - docs/runbooks/THIRD_PARTY_REVOCATION_RUNBOOK.md
  - tools/audit/check-third-party-revocation.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-third-party-revocation.ts
linked_issues: []
linked_prs:
  - local:e7a9866
owner: platform
runbook: docs/runbooks/THIRD_PARTY_REVOCATION_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Ships the database contract: public.third_party_revocations
  append-only queue (CHECK provider ∈ {strava, training_peaks},
  event ∈ 7 states, retry_count 0..20), auto-enqueue trigger on
  strava_connections DELETE, helpers fn_request_third_party_revocation
  / fn_third_party_revocations_due / fn_complete_third_party_revocation
  (SECURITY DEFINER, pinned search_path, service_role-only grants).
  State transitions are append-only rows linked by request_id —
  L10-08 keeps the log immutable. Self-test exercises enqueue → due
  → completed → DELETE-blocked + unknown-provider rejection.
  Follow-ups explicitly scoped out: L04-09-strava-worker (Edge Function
  that calls POST /oauth/deauthorize), L04-09-tp-worker (blocked on
  TrainingPeaks integration).
---
# [L04-09] Terceiros (Strava, TrainingPeaks) — não há processo de revogação
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/features/strava/presentation/strava_connect_controller.dart`: usuário autoriza Strava via OAuth, tokens salvos em `strava_connections`. Em `fn_delete_user_data` isso é deletado localmente, **mas o token permanece ativo no Strava**. Não há chamada `POST /oauth/deauthorize`.
## Risco / Impacto

— LGPD Art. 18, VIII (transferência a terceiros): dados continuam sendo puxados do Strava mesmo após "exclusão" da conta, se token sincronizar por webhook.

## Correção proposta

—

```typescript
// Inside fn_delete_user_data orchestration
const { data: stravaConn } = await adminDb.from("strava_connections")
  .select("access_token").eq("user_id", uid).maybeSingle();
if (stravaConn) {
  await fetch("https://www.strava.com/oauth/deauthorize", {
    method: "POST",
    headers: { Authorization: `Bearer ${stravaConn.access_token}` },
  });
}
// Same for TrainingPeaks via their revoke endpoint
```

E registrar o evento em `consent_log`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.9).