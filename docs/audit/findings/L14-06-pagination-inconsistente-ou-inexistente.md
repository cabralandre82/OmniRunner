---
id: L14-06
audit_ref: "14.6"
lens: 14
title: "Pagination inconsistente (ou inexistente)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["reliability"]
files:
  - portal/src/lib/api/pagination.ts
  - portal/src/lib/api/pagination.test.ts
  - portal/src/app/api/athletes/route.ts
  - portal/src/app/api/athletes/route.test.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/api/pagination.test.ts
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
  Fixed in commit `3ac1496`. New `lib/api/pagination.ts` defines
  the cursor-based pagination contract:

  - Request:    `?cursor=<opaque base64url>&limit=<1..100>`
  - Response:   `{ items: [...], next_cursor: string|null,
                  has_more: boolean }` (wrapped in the L14-05
                  canonical `{ ok: true, data }` envelope).
  - Defaults:   `DEFAULT_PAGE_LIMIT = 50`, `MAX_PAGE_LIMIT = 100`.
  - Cursors are JSON encoded as base64url; deliberately unsigned
    (RLS is the security boundary, not the cursor).
  - `paginate()` uses the over-fetch-by-one pattern with a typed
    `extractCursor` callback that runs only on the last visible
    row.

  Applied to `GET /api/athletes` as the canonical reference
  (paginates by `(display_name ASC, user_id ASC)`). Other list
  endpoints already returning bounded views (training-plan, etc.)
  are tracked for incremental migration in Wave 2.

  Backward compat: clients that previously called
  `GET /api/athletes` and consumed `data: AthleteRow[]` now
  receive `data: { items: AthleteRow[], next_cursor, has_more }`.
  Frontend dropdowns must read `data.items` and implement virtual
  scroll using `next_cursor` for groups with >50 athletes.
---
# [L14-06] Pagination inconsistente (ou inexistente)
> **Lente:** 14 — Contracts · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `GET /api/athletes` retorna todos (sem `limit`, `offset`, `cursor`). Grupo com 5000 atletas envia payload de MB.
## Correção proposta

— Cursor-based pagination padrão:

```typescript
GET /api/v1/athletes?cursor=xyz&limit=50
→ { items: [...], next_cursor: "abc", has_more: true }
```

Limite máximo server-side 100.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.6).