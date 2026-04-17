---
id: L17-01
audit_ref: "17.1"
lens: 17
title: "withErrorHandler não é usado em endpoints financeiros críticos"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "observability", "testing", "reliability"]
files:
  - portal/src/lib/api-handler.ts
  - portal/src/app/api/swap/route.ts
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
# [L17-01] withErrorHandler não é usado em endpoints financeiros críticos
> **Lente:** 17 — VP Eng · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/lib/api-handler.ts:10-30` exporta `withErrorHandler(handler, routeName)`. Grep em `/api/custody/route.ts`, `/api/swap/route.ts`, `/api/distribute-coins/route.ts`, `/api/custody/withdraw/route.ts` mostra que **nenhum** usa o wrapper. Cada endpoint tem seu próprio `try/catch` inconsistente (ver [14.5]).
## Risco / Impacto

—

- Erros não capturados por Sentry quando `try` não envolve linha problemática.
- `x-request-id` não propagado na resposta de erro.
- Mensagem de erro hardcoded em pt-BR ([7.1]).

## Correção proposta

— Refatorar:

```typescript
// portal/src/app/api/swap/route.ts
import { withErrorHandler } from "@/lib/api-handler";

export const POST = withErrorHandler(async (req) => {
  // actual logic, throw on errors
  // wrapper converts to JSON + logs + request_id
}, "api.swap.post");
```

Criar lint rule custom (`eslint-plugin-custom-omni`) que proíbe `export async function POST/GET/...` sem wrapper.

## Teste de regressão

— CI grep: `rg "^export async function (POST|GET|PUT|DELETE|PATCH)" portal/src/app/api` → deve retornar 0 matches (tudo deve vir de `withErrorHandler`).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.1).