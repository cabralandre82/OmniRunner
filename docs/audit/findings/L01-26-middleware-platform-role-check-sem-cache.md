---
id: L01-26
audit_ref: "1.26"
lens: 1
title: "Middleware — platform role check sem cache"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "cron", "performance", "cache", "fixed"]
files:
  - portal/src/middleware.ts
  - portal/src/lib/route-policy-cache.ts
  - tools/audit/check-k4-security-fixes.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 99ac6c7
  - 4d7950b
  - d63d253
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — process-local LRU cache for `profiles.platform_role`,
  mirroring the `coaching_members` cache from L13-03 but with a
  longer TTL (300 s vs 60 s) because platform_role demotions are
  rare. New helpers `getCachedPlatformRole`, `setCachedPlatformRole`,
  `invalidatePlatformRole`, `clearPlatformRoleCache` live in
  `lib/route-policy-cache.ts`. Middleware path
  `/platform/*` + `/api/platform/*` now performs at most one
  Postgres round-trip per cold cache window per user (was 1 per
  RSC). Negative caching uses literal `"none"` for inspector
  ergonomics.
---
# [L01-26] Middleware — platform role check sem cache
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** platform_admin
## Achado
`portal/src/middleware.ts:48-62` faz SELECT em `profiles` para checar `platform_role` **em cada request** para `/platform/*`. Latência por request. Sem cache. Um admin_platform com 10 req/s adiciona 10 queries/s desnecessárias.
## Risco / Impacto

Performance, não segurança.

## Correção proposta

Cachear em cookie `portal_platform_role` (httpOnly, 5min TTL) com revalidação assíncrona.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.26]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.26).