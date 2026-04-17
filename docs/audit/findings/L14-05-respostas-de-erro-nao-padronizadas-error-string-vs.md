---
id: L14-05
audit_ref: "14.5"
lens: 14
title: "Respostas de erro não padronizadas (error: string vs error: { code, message })"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/app/api/swap/route.ts
  - portal/src/app/api/athletes/route.ts
  - portal/src/lib/api/errors.ts
correction_type: code
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