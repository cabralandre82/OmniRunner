---
id: L01-25
audit_ref: "1.25"
lens: 1
title: "Middleware — PUBLIC_PREFIXES.some(p => pathname.startsWith(p))"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "portal", "testing", "fixed"]
files:
  - portal/src/lib/route-policy.ts
  - portal/src/lib/route-policy.test.ts
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/route-policy.test.ts
linked_issues: []
linked_prs:
  - e022472
  - 908a5b7
  - 27bc0f5
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — segment-shape contract for public deep-link prefixes.
  PUBLIC_PREFIX_PATTERNS pairs each public prefix with a regex that
  matches the FULL pathname, refusing nested segments. isPublicRoute
  short-circuits via the explicit pattern table; /api/cron/ keeps its
  bare prefix check (caller is gated by CRON_SECRET, L02-10). 38
  vitest cases cover canonical shapes, nested-admin attempts, charset
  injection, and the cron carve-out. Closes L13-08 by the same fix.
---
# [L01-25] Middleware — PUBLIC_PREFIXES.some(p => pathname.startsWith(p))
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Todos
## Achado
`portal/src/middleware.ts:30`: `pathname.startsWith("/challenge/")` — não impede `/challenge/../admin` pois o Next.js normaliza pathnames antes do middleware. **Provavelmente seguro**, mas vale teste manual.
  - `/challenge` sem trailing `/` **NÃO** é público (só `/challenge/` é). Isso é intencional (evitar listar desafios sem auth), mas pode causar 401 em links copiados sem slash final.
## Risco / Impacto

Baixo. Possível evasão se houver URL rewrite middleware intermediário.

## Correção proposta

Adicionar test E2E verificando que `/challenge/../platform/custody` cai em 401.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.25]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.25).