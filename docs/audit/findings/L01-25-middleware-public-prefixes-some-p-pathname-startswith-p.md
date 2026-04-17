---
id: L01-25
audit_ref: "1.25"
lens: 1
title: "Middleware — PUBLIC_PREFIXES.some(p => pathname.startsWith(p))"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "testing"]
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