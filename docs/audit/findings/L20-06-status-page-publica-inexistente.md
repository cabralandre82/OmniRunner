---
id: L20-06
audit_ref: "20.6"
lens: 20
title: "Status page pública inexistente"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: [sre, status-page, public-api, observability]
files:
  - portal/src/lib/status/types.ts
  - portal/src/lib/status/aggregate.ts
  - portal/src/lib/status/feeds.ts
  - portal/src/lib/status/__tests__/aggregate.test.ts
  - portal/src/app/api/public/status/route.ts
  - tools/audit/check-public-status.ts
  - docs/runbooks/PUBLIC_STATUS_PAGE_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - portal/src/lib/status/__tests__/aggregate.test.ts
linked_issues: []
linked_prs:
  - local:ca43e64
owner: sre
runbook: docs/runbooks/PUBLIC_STATUS_PAGE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Ships the aggregator + public endpoint
  (`GET /api/public/status`) consumed by the future
  `status.omnirunner.com`. Domain layer in
  `portal/src/lib/status/` with 6 canonical components
  (web/api/database/auth/payments/strava), 5-level severity
  ladder matching Atlassian/Better-Stack wire contract,
  TTL-cached (60s, floor 30s pinned by CI), never-5xx contract
  (feed throws coerced to `unknown`), CORS-permissive (GET +
  OPTIONS preflight). Tests: 27 vitest cases. CI:
  `npm run audit:public-status` (46/46 checks). Deferred:
  `L20-06-external-feeds` (Vercel/Supabase/Stripe/Strava
  adapters), `L20-06-incident-timeline`, `L20-06-site`
  (status page itself), `L20-06-i18n`,
  `L20-06-admin-invalidate`, `L20-06-rate-limit`.
---
# [L20-06] Status page pública inexistente
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Usuário não tem onde ver "Omni Runner está operacional?". Em outage, support tickets inundam.
## Correção proposta

— `status.omnirunner.com` via Atlassian Statuspage, Better Stack, ou self-hosted Cachet. Feeds consumem Vercel + Supabase + Stripe status APIs + `/api/health`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.6).
- `2026-04-21` — **Corrigido** (commit `ca43e64`): aggregator puro + endpoint `GET /api/public/status` (público, CORS-aberto, never-5xx, TTL-cache com piso de 30 s). Domínio em `portal/src/lib/status/` cobre 6 componentes canônicos, 5 níveis de severidade (operational/degraded/partial_outage/major_outage/unknown), worst-wins, graceful degradation (vendor outage → `unknown`, nunca 5xx). 27 unit tests + CI guard `npm run audit:public-status` (46 checks). Runbook: [PUBLIC_STATUS_PAGE_RUNBOOK.md](../../runbooks/PUBLIC_STATUS_PAGE_RUNBOOK.md). Follow-ups: `L20-06-external-feeds`, `L20-06-incident-timeline`, `L20-06-site`, `L20-06-i18n`, `L20-06-admin-invalidate`, `L20-06-rate-limit`.