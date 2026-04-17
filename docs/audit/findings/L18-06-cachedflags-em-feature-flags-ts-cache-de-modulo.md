---
id: L18-06
audit_ref: "18.6"
lens: 18
title: "cachedFlags em feature-flags.ts — cache de módulo com TTL racional"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "portal", "edge-function", "migration"]
files:
  - portal/src/lib/feature-flags.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L18-06] cachedFlags em feature-flags.ts — cache de módulo com TTL racional
> **Lente:** 18 — Principal Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/lib/feature-flags.ts:9-11`:

```9:11:portal/src/lib/feature-flags.ts
let cachedFlags: Map<string, Flag> | null = null;
let lastFetchMs = 0;
const TTL_MS = 60_000;
```

Cache em escopo de módulo (edge function = por instância serverless). Cada instância Vercel tem seu cache; 60s TTL. Aceitável. Mas admin toggle leva até 60s pra propagar (feature-flag de emergência para cortar operação financeira — [6.6] — deve ser instantâneo).
## Correção proposta

— Para flags **críticas** (`custody.*.enabled`), TTL = 5s. Ou propagação via Supabase Realtime broadcast:

```typescript
supabase.channel("feature-flags").on("postgres_changes", {
  event: "UPDATE", schema: "public", table: "feature_flags"
}, () => { cachedFlags = null; lastFetchMs = 0; }).subscribe();
```

Realtime só funciona em instância long-lived → em serverless Vercel não resolve. Alternativa: `rollout_pct = 0` no DB + invalidação por `POST /api/internal/flags/invalidate` chamado broadcast a todas as instâncias (via Vercel Edge Config ou similar).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.6).