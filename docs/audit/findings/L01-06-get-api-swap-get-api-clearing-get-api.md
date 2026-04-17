---
id: L01-06
audit_ref: "1.6"
lens: 1
title: "GET /api/swap, GET /api/clearing, GET /api/custody — Autorização por cookie"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "security-headers", "portal", "reliability"]
files:
  - portal/src/middleware.ts
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