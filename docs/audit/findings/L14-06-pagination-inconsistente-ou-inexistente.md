---
id: L14-06
audit_ref: "14.6"
lens: 14
title: "Pagination inconsistente (ou inexistente)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["reliability"]
files: []
correction_type: config
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