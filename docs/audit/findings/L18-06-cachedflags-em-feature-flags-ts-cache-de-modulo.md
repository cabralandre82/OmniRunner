---
id: L18-06
audit_ref: "18.6"
lens: 18
title: "cachedFlags em feature-flags.ts — cache de módulo com TTL racional"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "portal", "edge-function", "migration"]
files:
  - portal/src/lib/feature-flags.ts
  - portal/src/lib/feature-flags.test.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/feature-flags.test.ts
linked_issues: []
linked_prs:
  - "commit:34d9018"
owner: backend
runbook: docs/runbooks/FEATURE_FLAGS_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Implementada estratificação de TTL por categoria de flag em
  `portal/src/lib/feature-flags.ts`. A função `loadFlags()` agora calcula
  o TTL efetivo via `effectiveTtlMs(cache)` — se qualquer flag em cache
  tiver `category='kill_switch'`, o TTL passa de 60s (`TTL_MS`) para 5s
  (`KILL_SWITCH_TTL_MS`). Solução de cache único evita race entre dois
  caches paralelos e preserva a invalidação local existente em
  `setFeatureFlag()` (writer instance vê efeito imediato).

  Resultado operacional: um flip de kill switch (e.g.
  `custody.withdrawals.enabled = false`) propaga em ≤5s pelo fleet de
  serverless instances, contra os ≤60s anteriores. O custo é ~12x mais
  reads na tabela `feature_flags`, que tem dígito único de linhas — DB
  pressure desprezível. Para flags não-críticas (`product`,
  `experimental`, `banner`, `operational`), nada muda: TTL permanece em
  60s.

  Cobertura de testes: 3 novos casos em `feature-flags.test.ts` validam
  (a) presença de kill switch força TTL de 5s, (b) ausência preserva
  60s, e (c) propagação end-to-end de um toggle de kill switch dentro de
  ~5s. Suite portal: 1078 → 1085 passando.
---
# [L18-06] cachedFlags em feature-flags.ts — cache de módulo com TTL racional
> **Lente:** 18 — Principal Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
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