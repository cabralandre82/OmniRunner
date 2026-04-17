---
id: L01-21
audit_ref: "1.21"
lens: 1
title: "rateLimit no portal — Fail-open para memory"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "rate-limit", "portal", "observability", "reliability"]
files:
  - portal/src/lib/rate-limit.ts
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
# [L01-21] rateLimit no portal — Fail-open para memory
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Todos
## Achado
`portal/src/lib/rate-limit.ts:97-100` — se Redis falhar, cai para `rateLimitInMemory`. Em Vercel Serverless, **cada invocação pode ser instância nova**, então memory store é efetivamente **rate-limit desligado** (cada lambda começa com Map vazio).
  - `_hasRedis = !!getRedis()` (linha 105) é **cacheado em module init**. Se Redis config aparecer depois de start, rate limit nunca usa Redis. Crítico para deploys a quente / mudança de env.
## Risco / Impacto

DoS durante degradação Redis. Brute-force possível em endpoints sensíveis (login via Supabase — embora a própria Supabase tenha rate limit no lado dela).

## Correção proposta

1. Mover `_hasRedis` para avaliação por request (`getRedis() !== null`) ou re-checar a cada 60s.
  2. Em fallback memory durante invocação serverless, **fail-closed** em endpoints financeiros (custody, withdraw, distribute, swap): retornar 503 se Redis indisponível.
  3. Adicionar métrica Sentry `rate-limit.fallback.memory.count` para alertar SRE.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.21]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.21).