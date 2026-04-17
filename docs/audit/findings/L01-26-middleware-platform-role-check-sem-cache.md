---
id: L01-26
audit_ref: "1.26"
lens: 1
title: "Middleware — platform role check sem cache"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal", "cron", "performance"]
files:
  - portal/src/middleware.ts
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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