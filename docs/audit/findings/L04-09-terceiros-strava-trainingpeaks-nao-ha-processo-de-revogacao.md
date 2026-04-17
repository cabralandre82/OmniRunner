---
id: L04-09
audit_ref: "4.9"
lens: 4
title: "Terceiros (Strava, TrainingPeaks) — não há processo de revogação"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "webhook", "security-headers", "integration", "mobile", "cron"]
files:
  - omni_runner/lib/features/strava/presentation/strava_connect_controller.dart
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