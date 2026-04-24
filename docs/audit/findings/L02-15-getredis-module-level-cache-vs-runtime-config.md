---
id: L02-15
audit_ref: "2.15"
lens: 2
title: "getRedis() — Module-level cache vs runtime config"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "redis", "fixed"]
files:
  - portal/src/lib/redis.ts
  - portal/src/lib/rate-limit.ts
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
  K4 batch — `getRedis()` no longer caches the (no-config) state
  forever. We re-read process.env every `RECHECK_INTERVAL_MS` (60 s)
  and rebuild the client when the env tuple (URL + token length)
  changes. A hot lambda whose first invocation observed "no Redis"
  now upgrades to Redis within one minute of the env being fixed.
  New helper `isRedisAvailable()` exposes the same recheck signal
  to callers (used by `rateLimit` to branch between
  `degrade`/`fail_closed` modes — see L01-21).
---
# [L02-15] getRedis() — Module-level cache vs runtime config
> **Lente:** 2 — CTO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
_(sem descrição detalhada — ver relatório original em `docs/audit/parts/`)_
## Correção proposta

Ver [1.21].

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.15).