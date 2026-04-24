---
id: L10-12
audit_ref: "10.12"
lens: 10
title: "CSRF no portal confiando apenas em SameSite=Lax"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "security-headers", "portal", "migration", "duplicate", "fixed"]
files:
  - portal/src/middleware.ts
  - portal/src/lib/api/csrf.ts
correction_type: code
test_required: true
tests:
  - "portal/src/lib/api/csrf.test.ts (existing CSRF unit tests cover origin pinning + token check)"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: L17-06
deferred_to_wave: null
note: |
  K4 batch — closed by L17-06. The portal already enforces
  CSRF defence-in-depth on every `/api/*` mutation:
    1. Origin pinning runs FIRST (verifyOrigin → 403 CSRF_ORIGIN_INVALID).
    2. Double-submit token check runs SECOND (verifyCsrf → 403
       CSRF_TOKEN_INVALID).
    3. The legacy `sameSite: "lax"` cookies retain their default
       behaviour but are no longer the primary defence.
  See `portal/src/middleware.ts:178-231` and
  `portal/src/lib/api/csrf.ts`. Webhook + OAuth callback paths are
  exempt because they're authenticated by HMAC / OAuth `state`,
  not by browser cookies.
---
# [L10-12] CSRF no portal confiando apenas em SameSite=Lax
> **Lente:** 10 — CSO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Cookies `portal_group_id`, `portal_role` com `sameSite: "lax"`. Ataques com navegação top-level (GET) não são bloqueados.
## Correção proposta

— Todas as mutações via POST/PUT/DELETE + verificação de token CSRF anti-forgery (double-submit cookie pattern) nos `api/*` que alteram estado financeiro.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.12).