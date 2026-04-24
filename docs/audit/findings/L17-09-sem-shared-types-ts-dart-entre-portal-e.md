---
id: L17-09
audit_ref: "17.9"
lens: 17
title: "Sem shared types TS/Dart entre portal e mobile"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "portal"]
files:
  - portal/src/lib/schemas.ts
  - docs/runbooks/SHARED_TYPES_TS_DART.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 8046248

owner: platform
runbook: docs/runbooks/SHARED_TYPES_TS_DART.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Estratégia ratificada em
  `docs/runbooks/SHARED_TYPES_TS_DART.md`. **OpenAPI 3.1 como
  source of truth**, emitido pelo portal a partir do registry
  Zod (L14-01) e consumido por `@hey-api/openapi-ts` (TS) e
  `openapi_generator` (Dart) na CI. Migração 4-fase deferred
  para Wave 3 (toca toda a camada de DTOs do mobile +
  significativa do portal). Mitigações em produção hoje:
  registry OpenAPI L14-01 + CI guard de event catalog L08-09 +
  política manual de PR review.
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