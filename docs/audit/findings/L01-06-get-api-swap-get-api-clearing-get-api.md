---
id: L01-06
audit_ref: "1.6"
lens: 1
title: "GET /api/swap, GET /api/clearing, GET /api/custody — Autorização por cookie"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "security-headers", "portal", "reliability"]
files:
  - portal/src/middleware.ts
  - portal/src/lib/route-policy.ts
  - portal/src/lib/actions.ts
  - portal/src/app/api/set-group/route.ts
  - portal/src/lib/api/csrf.ts
  - portal/src/lib/api/csrf-fetch.ts
  - portal/src/app/(portal)/fx/withdraw-button.tsx
  - portal/src/app/(portal)/athletes/distribute-button.tsx
  - portal/src/app/(portal)/custody/deposit-button.tsx
  - portal/src/app/(portal)/swap/swap-actions.tsx
  - portal/src/app/platform/feature-flags/feature-flag-row.tsx
  - portal/src/app/platform/fees/fee-row.tsx
  - portal/src/app/platform/reembolsos/actions.tsx
correction_type: code
test_required: true
tests:
  - portal/src/lib/api/csrf.test.ts
  - portal/src/lib/api/csrf-fetch.test.ts
  - portal/src/lib/route-policy.test.ts
linked_issues: []
linked_prs:
  - "commit:7fbc4ec"
owner: portal-team
runbook: docs/runbooks/CSRF_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Mitigated with two layers of defence so a single regression in either
  layer does not re-open the CSRF surface:

  1. **`sameSite: "strict"` on session cookies.** `portalCookieOptions()`
     in `lib/route-policy.ts` flips `portal_group_id` and `portal_role`
     from `lax` → `strict`. Lax cookies were sent on top-level GET
     navigation from any origin, which combined with the cookie-driven
     `requireAdminMaster()` flow created a CSRF vector on the financial
     GET endpoints called out by the finding. Strict eliminates that
     path entirely. The two divergent inline cookie-opts blocks
     (`api/set-group/route.ts` and `lib/actions.ts`) were refactored
     to use `portalCookieOptions()` so the policy can never drift
     again.

  2. **Double-submit CSRF token.** New `lib/api/csrf.ts` implements an
     OWASP-Cheat-Sheet-2024 §3.2 stateless double-submit token:
     - `portal_csrf` cookie (32 bytes hex, `sameSite: "strict"`,
       `httpOnly: false` so client JS can mirror it as a header) is
       issued by middleware on every authenticated response.
     - `verifyCsrf` constant-time-compares the cookie against the
       `x-csrf-token` request header on `(POST|PUT|PATCH|DELETE)` to
       the financial allow-list (custody/withdraw/swap/clearing/
       distribute-coins + platform custody/feature-flags/fees/
       refunds). Mismatch returns 403 `CSRF_TOKEN_INVALID` *before*
       auth (cheap pure check, no Postgres round-trip on attacker
       traffic).
     - Exempt: `/api/custody/webhook`, `/api/billing/asaas` (HMAC),
       `/api/auth/callback` (OAuth `state`).

  3. **Browser wrapper `csrfFetch`** mirrors the cookie into the header
     automatically. The 7 financial UI components were migrated to it,
     and the withdraw button additionally generates a fresh
     `x-idempotency-key` per submit (a latent L18-02 regression
     uncovered during this fix).

  4. **`signOut`** now deletes `portal_csrf` so the next session gets
     a fresh token rather than inheriting the previous user's value.

  Out of scope for L01-06 (tracked separately):
  - Removing `'unsafe-inline'` from CSP — Lente 20.x.
  - Promoting `/api/announcements`, `/api/team/*`, etc. to the CSRF
    allow-list — not in the financial surface called out by this
    finding; future hardening can extend `CSRF_PROTECTED_PREFIXES`.
---
# [L01-06] GET /api/swap, GET /api/clearing, GET /api/custody — Autorização por cookie
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Coach/Assistant (potencial escalação)
## Achado
Os helpers `requireAdminMaster` (`/api/custody/route.ts:24-48`, `/api/custody/withdraw/route.ts:23-47`, `/api/swap/route.ts:32-56`) consultam a role do usuário **a partir do cookie `portal_group_id`** (`cookies().get("portal_group_id")?.value`). Embora o middleware (`portal/src/middleware.ts:82-103`) revalide a membership a cada request, um agressor que consiga setar cookies (via XSS com `'unsafe-inline'` no CSP — LENTE 7.5 / 20.x) pode assumir a identidade de assessoria alheia se ele tiver membership em qualquer grupo e forjar outro `portal_group_id`. A revalidação rejeita, mas para tabelas em que ele *é* `admin_master` de um grupo, assumir outro cookie não escala (middleware confere `user_id + group_id`).
## Risco / Impacto

Defesa em profundidade frágil: CSP `'unsafe-inline'` (next.config.mjs:78-80) + cookie de grupo httpOnly+sameSite:lax (`portal/src/middleware.ts:97-102`) — lax ainda permite top-level navegação GET. Se uma rota GET não exigir método POST, é CSRF-exploitable.

## Correção proposta

Adicionar `sameSite: "strict"` aos cookies `portal_group_id` e `portal_role`, ou adicionar header `X-CSRF-Token` validado em todos os POSTs. Remover `'unsafe-inline'` do CSP (LENTE 20.x).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.6).
- `2026-04-17` — **Corrigido** (commit `7fbc4ec`): `sameSite: "strict"`
  nos cookies de sessão portal + middleware CSRF double-submit
  token gating financial mutation surface. Runbook em
  `docs/runbooks/CSRF_RUNBOOK.md`. 30 testes novos (`csrf.test.ts`
  21 + `csrf-fetch.test.ts` 9) + atualização de `route-policy.test.ts`.