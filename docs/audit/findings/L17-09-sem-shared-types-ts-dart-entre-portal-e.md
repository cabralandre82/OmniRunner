---
id: L17-09
audit_ref: "17.9"
lens: 17
title: "Sem shared types TS/Dart entre portal e mobile"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/lib/schemas.ts
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L17-09] Sem shared types TS/Dart entre portal e mobile
> **Lente:** 17 — VP Eng · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/lib/schemas.ts` define Zod schemas; mobile Flutter re-define manualmente em `lib/domain/entities/*.dart`. Divergência potencial.
## Correção proposta

— `packages/shared-contracts/` gerando:

- TS types a partir de Zod
- Dart classes via `freezed` + `json_serializable`
- OpenAPI JSON único fonte da verdade

Ferramenta: `@hey-api/openapi-ts` (TS) + `openapi_generator` (Dart).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.9).