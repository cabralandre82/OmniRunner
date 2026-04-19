---
id: L14-01
audit_ref: "14.1"
lens: 14
title: "74 route handlers, 46 documentados em OpenAPI"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "mobile", "portal", "reliability"]
files:
  - portal/src/lib/openapi/registry.ts
  - portal/src/lib/openapi/build.ts
  - portal/src/lib/openapi/routes/v1-financial.ts
  - portal/tools/openapi/build.ts
  - portal/tools/openapi/check-coverage.ts
  - portal/tools/openapi/refresh-baseline.ts
  - portal/tools/openapi/coverage-baseline.json
  - portal/public/openapi-v1.json
  - portal/src/app/api/docs/route.ts
correction_type: process
test_required: true
tests:
  - portal/src/lib/openapi/build.test.ts
linked_issues: []
linked_prs:
  - 88ba7e0
owner: backend-platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Adotada estratégia contract-first com `@asteasolutions/zod-to-openapi`:
  - `lib/openapi/registry.ts` — registry compartilhado + schemas
    centrais (`ApiErrorBody`, `ApiOkMarker`, `DecimalAmount`,
    `IdempotencyKey`, `STD_ERROR_RESPONSES`, `STD_API_HEADERS`).
  - `lib/openapi/build.ts` — gera OpenAPI 3.1 determinístico a partir
    dos Zod schemas (mesma entrada → JSON byte-idêntico, pré-requisito
    do drift gate).
  - `lib/openapi/routes/v1-financial.ts` — registra os 5 endpoints v1
    financeiros como exemplares contract-first (swap, custody,
    custody/withdraw, distribute-coins, clearing).
  - `tools/openapi/build.ts` (npm run openapi:build) — regenera
    `public/openapi-v1.json` a partir do registry.
  - `tools/openapi/check-coverage.ts` (npm run openapi:check) — DOIS
    gates em um:
      (a) DRIFT — falha se o arquivo committado ≠ output do registry;
      (b) COVERAGE — falha se uma rota nova existe sem documentação e
          fora do baseline grandfathered.
  - `tools/openapi/coverage-baseline.json` — snapshot dos 30 routes
    atualmente sem documentação (mostly /api/training-plan/*),
    grandfathered. A lista pode encolher; o gate impede que cresça.
  - `/api/docs` (Swagger UI) agora expõe ambos os specs via dropdown
    ("v1 (generated)" default; "v0 (legacy)" alternate).

  Entregue: framework + drift gate + 5 exemplares v1 + baseline
  congelado. A migração das 30 rotas grandfathered é decremento
  contínuo PR-a-PR — o gate impede regressão.

  Commits:
    - 88ba7e0 (feat OpenAPI registry + drift gate + v1 exemplars)
---
# [L14-01] 74 route handlers, 46 documentados em OpenAPI
> **Lente:** 14 — Contracts · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
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