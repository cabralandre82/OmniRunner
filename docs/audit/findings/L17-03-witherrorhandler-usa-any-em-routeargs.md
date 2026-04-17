---
id: L17-03
audit_ref: "17.3"
lens: 17
title: "withErrorHandler usa any em routeArgs"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "migration"]
files:
  - portal/src/lib/api-handler.ts
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
# [L17-03] withErrorHandler usa any em routeArgs
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linha 11:

```11:11:portal/src/lib/api-handler.ts
  handler: (req: NextRequest, ...routeArgs: any[]) => Promise<NextResponse>,
```

`any` derrota o type-checking em favor de ergonomia.
## Correção proposta

—

```typescript
export function withErrorHandler<TArgs extends unknown[]>(
  handler: (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse>,
  routeName: string,
): (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse> {
  return async (req, ...args) => { ... };
}
```

Mais: habilitar `"noImplicitAny": true` em `tsconfig.json` e rodar `npx tsc --noEmit --strict`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.3).