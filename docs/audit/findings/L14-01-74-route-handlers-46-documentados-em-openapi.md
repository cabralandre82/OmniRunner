---
id: L14-01
audit_ref: "14.1"
lens: 14
title: "74 route handlers, 46 documentados em OpenAPI"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "mobile", "portal", "reliability"]
files:
  - portal/src/lib/openapi.ts
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
# [L14-01] 74 route handlers, 46 documentados em OpenAPI
> **Lente:** 14 — Contracts · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `find portal/src/app/api -name route.ts` → 74 arquivos. `grep '"/api' openapi.json` → 46 matches. **~28 endpoints não documentados**.
## Risco / Impacto

— Parceiros B2B chamam endpoints sem contrato. Devs mudam signature, clientes quebram sem aviso.

## Correção proposta

— Contract-first:

1. Adotar **tRPC** (type-safe RPC gerando client TS) OU
2. Gerar OpenAPI a partir dos Zod schemas com `@asteasolutions/zod-to-openapi`:

```typescript
// portal/src/lib/openapi.ts
import { OpenAPIRegistry, OpenApiGeneratorV31 } from "@asteasolutions/zod-to-openapi";
import { distributeCoinsSchema, custodyDepositSchema, ... } from "./schemas";

export const registry = new OpenAPIRegistry();
registry.registerPath({
  method: "post", path: "/api/distribute-coins",
  request: { body: { content: { "application/json": { schema: distributeCoinsSchema } } } },
  responses: { 200: { description: "ok" }, 422: { description: "validation" } },
});
// ... for all 74

// Regenerate openapi.json in CI; fail if drift
```

CI step: `diff public/openapi.json <(npm run generate-openapi)` → falha se diff.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.1).