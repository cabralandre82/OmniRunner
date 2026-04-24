---
id: L01-21
audit_ref: "1.21"
lens: 1
title: "rateLimit no portal — Fail-open para memory"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "rate-limit", "portal", "observability", "reliability", "fixed"]
files:
  - portal/src/lib/rate-limit.ts
  - portal/src/lib/redis.ts
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/custody/route.ts
  - portal/src/app/api/distribute-coins/route.ts
  - portal/src/app/api/distribute-coins/batch/route.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/app/api/coins/reverse/route.ts
  - tools/audit/check-k4-security-fixes.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 99ac6c7
  - 4d7950b
  - 5fc0aee
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — `rateLimit()` gains an `onMissingRedis` option:
    • `degrade` (default) — keep legacy in-memory fallback for
      low-risk surfaces (e.g. invite, branding, attribution).
    • `fail_closed` — return `allowed: false` immediately when
      Redis is missing. Wired on every financial mutation:
        - POST /api/custody (deposit)
        - POST /api/custody/withdraw
        - POST /api/distribute-coins
        - POST /api/distribute-coins/batch
        - POST /api/swap
        - POST /api/coins/reverse
  Telemetry counters (`rateLimitTelemetrySnapshot`) expose
  `failClosedHits` and `fallbackHits` for SRE dashboards.
  `getRedis()` is now request-aware (60 s recheck, see L02-15)
  so a hot-deployed env-var change lands within one minute.
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