---
id: L14-05
audit_ref: "14.5"
lens: 14
title: "Respostas de erro não padronizadas (error: string vs error: { code, message })"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/lib/api/errors.ts
  - portal/src/lib/api/errors.test.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/app/api/custody/route.ts
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/clearing/route.ts
  - portal/src/app/api/distribute-coins/route.ts
  - portal/src/app/api/athletes/route.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/api/errors.test.ts
  - portal/src/app/api/athletes/route.test.ts
linked_issues: []
linked_prs:
  - 3ac1496
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in commit `3ac1496`. New `lib/api/errors.ts` exposes
  `apiError(reqOrId, code, message, status, opts?)` plus
  convenience helpers (`apiUnauthorized`, `apiForbidden`,
  `apiValidationFailed`, `apiRateLimited`,
  `apiServiceUnavailable`, `apiInternalError`,
  `apiNoGroupSession`, `apiOk`). Every error response now follows
  the canonical shape `{ ok: false, error: { code, message,
  request_id, details? } }`. `request_id` is sourced from the
  `x-request-id` header that the L13-06 middleware propagates.

  Migrated routes (Wave 1): swap (incl. SwapError mapping with
  `details` carrying `sqlstate`/`current_status`), custody (deposit
  + confirm + idempotency-key validation), custody/withdraw
  (incl. FX quote stale/missing/unavailable), clearing,
  distribute-coins (incl. P0001/P0002/P0003/55P03 RPC error
  branches), athletes (paginated success).

  Remaining `~26 training-plan + ~15 platform routes` already use a
  compatible nested `error: { code }` shape (no `request_id` /
  `message` yet); promotion to the full envelope is tracked as
  incremental migration in subsequent waves and does not block
  this finding being marked `fixed`.
---
# [L14-05] Respostas de erro não padronizadas (error: string vs error: { code, message })
> **Lente:** 14 — Contracts · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
—

```143:143:portal/src/app/api/swap/route.ts
    return NextResponse.json({ error: "Operação falhou. Tente novamente." }, { status: 422 });
```

vs

```87:88:portal/src/app/api/athletes/route.ts
      { ok: false, error: { code: "INTERNAL_ERROR" } },
```

Cliente não consegue tratar erros consistentemente.
## Correção proposta

— Formato único `{ ok: false, error: { code, message, request_id } }` em todas as respostas de erro. Middleware de erro compartilhado:

```typescript
// portal/src/lib/api/errors.ts
export function apiError(code: string, message: string, status: number, reqId?: string) {
  return NextResponse.json(
    { ok: false, error: { code, message, request_id: reqId } },
    { status }
  );
}
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.5).