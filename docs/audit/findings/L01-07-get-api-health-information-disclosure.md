---
id: L01-07
audit_ref: "1.7"
lens: 1
title: "GET /api/health — Information disclosure"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "mobile", "portal", "migration", "ciso", "observability"]
files:
  - portal/src/app/api/health/route.ts
  - portal/src/app/api/platform/health/route.ts
  - portal/src/middleware.ts
correction_type: code
test_required: true
tests:
  - portal/src/app/api/health/route.test.ts
  - portal/src/app/api/platform/health/route.test.ts
  - portal/e2e/health.spec.ts
linked_issues: []
linked_prs: ["810b1fc"]
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Closed by the same change that fixed L06-02. Public `/api/health`
  now returns ONLY `{ status, ts }` — no `latencyMs`, no `checks`,
  no invariant count. Admin detail moved to `/api/platform/health`
  gated by `platform_admins` membership. See
  `docs/audit/findings/L06-02-health-check-exibe-contagem-exata-de-violacoes-info.md`
  for the full write-up; this Medium sibling flagged the same leak
  from the reconnaissance-risk angle and is closed by the same commit.
---
# [L01-07] GET /api/health — Information disclosure
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed (2026-04-21)
**Camada:** PORTAL
**Personas impactadas:** Qualquer atacante externo
## Achado
`portal/src/app/api/health/route.ts` retornava `{ status, latencyMs, checks: { db, invariants: "N violation(s)" } }`. Revelava **contagem exata de violações de invariante** ao público. Um atacante externo — ou funcionário suspenso — podia usar isso para inferir atividade de clearing e timing de ataque.

## Risco / Impacto

Baixo-médio — vaza sinais operacionais para reconnaissance.

## Correção implementada

- Endpoint público reduzido a `{ status, ts }`. Checks continuam
  rodando para diferenciar 200 vs 503, mas o payload não expõe
  detalhe algum a callers anônimos.
- Endpoint admin `/api/platform/health` criado para operadores com
  o payload detalhado (latency + checks + invariant_count) atrás
  de autenticação `platform_admins`.
- O middleware `portal/src/middleware.ts` mantém `/api/health`
  público (uptime probes continuam funcionando) e trata
  `/api/platform/health` via `/api/platform/` prefix
  (AUTH_ONLY_PREFIXES) como o resto dos endpoints admin.

Detalhe completo: [`L06-02`](./L06-02-health-check-exibe-contagem-exata-de-violacoes-info.md).

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — anchor `[1.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.7).
- `2026-04-21` — Fixed pelo mesmo commit que fechou L06-02.
