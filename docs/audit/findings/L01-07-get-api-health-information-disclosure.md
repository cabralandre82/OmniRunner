---
id: L01-07
audit_ref: "1.7"
lens: 1
title: "GET /api/health — Information disclosure"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "migration"]
files:
  - portal/src/app/api/health/route.ts
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
# [L01-07] GET /api/health — Information disclosure
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Qualquer atacante externo
## Achado
`portal/src/app/api/health/route.ts:37-48` retorna `{ status, latencyMs, checks: { db, invariants: "N violation(s)" } }`. Revela **contagem exata de violações de invariante** ao público. Um atacante interno (funcionário suspenso) pode usar isso para inferir atividade de clearing.
## Risco / Impacto

Baixo-médio — vaza sinais operacionais para reconnaissance.

## Correção proposta

Separar `/api/liveness` (público, apenas boolean) de `/api/health` (restrito a PLATFORM_ADMIN ou IP allowlist de monitoramento). Middleware atual (`portal/src/middleware.ts:4`) marca ambos como public — restringir `/api/health` a IPs Vercel/Cloudflare.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.7).