---
id: L06-02
audit_ref: "6.2"
lens: 6
title: "Health check exibe contagem exata de violações (info leak operacional)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal", "migration", "testing"]
files:
  - portal/src/app/api/health/route.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L06-02] Health check exibe contagem exata de violações (info leak operacional)
> **Lente:** 6 — COO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/health/route.ts:44`:

```44:44:portal/src/app/api/health/route.ts
        invariants: invariantsOk ? "healthy" : `${invariantCount} violation(s)`,
```

Endpoint é público (nenhum auth). Atacante monitora: "7 violations" → sabe que plataforma está comprometida → timing de ataque + extorsão ("pague ou divulgo").
## Risco / Impacto

— Information disclosure. Também expõe latência de DB (`latencyMs`) que ajuda fingerprinting.

## Correção proposta

—

```typescript
const body = allOk
  ? { status: "ok", ts: Date.now() }
  : { status: dbOk ? "degraded" : "down", ts: Date.now() };

// Full details only when ?secret=... matches env
const full = new URL(req.url).searchParams.get("secret") === process.env.HEALTH_SECRET;
if (full) {
  body.checks = { db: ..., invariants: ..., invariantCount };
  body.latencyMs = latencyMs;
}
```

E adicionar endpoint separado `/api/internal/health-detailed` protegido por JWT platform_admin.

## Teste de regressão

— `health.test.ts`: GET sem secret → body tem apenas `status` e `ts`; com secret → inclui detalhes.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.2).