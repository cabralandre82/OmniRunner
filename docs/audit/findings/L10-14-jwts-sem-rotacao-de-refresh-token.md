---
id: L10-14
audit_ref: "10.14"
lens: 10
title: "JWTs sem rotação de refresh_token"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: []
files:
  - docs/security/REFRESH_TOKEN_ROTATION.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - d3488b4
  - 4a7a2c9
owner: security+platform
runbook: docs/security/REFRESH_TOKEN_ROTATION.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Policy ratified in docs/security/REFRESH_TOKEN_ROTATION.md:
  Refresh Token Rotation = ON, Reuse Interval = 0,
  Rotation Period = 10s, JWT Expiry = 1h, Refresh Expiry = 30d.
  Rationale: reuse triggers refresh_token_reused event,
  which we ingest into audit_logs (event_domain='auth',
  L18-09 dotted-domain naming) and revokes ALL of the
  user's sessions. Settings live in Supabase Dashboard +
  this doc + docs/runbooks/SUPABASE_AUTH_BOOTSTRAP.md;
  drift caught (planned) by tools/audit/check-supabase-auth-config.ts
  via Management API GET /v1/projects/{ref}/config/auth.
  Manual quarterly review until the API guard ships.
---
# [L10-14] JWTs sem rotação de refresh_token
> **Lente:** 10 — CSO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Supabase default: refresh_token "rotation" disponível via setting; não auditado se ativado.
## Correção proposta

— Confirmar em Supabase Dashboard: "Refresh Token Rotation" = `ON`, "Rotation Period" = 10s, "Reuse Interval" = 0.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.14).