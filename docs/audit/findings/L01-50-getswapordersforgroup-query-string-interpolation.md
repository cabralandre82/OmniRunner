---
id: L01-50
audit_ref: "1.50"
lens: 1
title: "getSwapOrdersForGroup — Query string interpolation"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "atomicity", "security-headers", "integration", "mobile", "portal", "fixed"]
files:
  - portal/src/lib/swap.ts
  - portal/src/lib/clearing.ts
  - portal/src/lib/security/uuid-guard.ts
  - portal/src/lib/security/uuid-guard.test.ts
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: true
tests:
  - "portal/src/lib/security/uuid-guard.test.ts (10 vitest cases)"
  - "npm run audit:k3-domain-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — pure-domain UUID guard:
    • new portal/src/lib/security/uuid-guard.ts (no I/O):
        isUuid · assertUuid · buildOrEqExpression(colA, colB, uuid, label)
      validates strict v1-5 UUID and refuses unsafe column identifiers.
    • swap.ts:getSwapOrdersForGroup and clearing.ts:getSettlementsForGroup
      now compose .or() filters via buildOrEqExpression — any non-uuid
      groupId throws InvalidUuidError before reaching PostgREST.
    • 10 vitest cases cover injection-style payloads (commas, parens,
      semicolons) and non-string inputs.
---
# [L01-50] getSwapOrdersForGroup — Query string interpolation
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Assessoria
## Achado
`portal/src/lib/swap.ts:134`: 
  ```typescript
  .or(`seller_group_id.eq.${groupId},buyer_group_id.eq.${groupId}`)
  ```
  Se `groupId` não é UUID (vem de cookie decodificado, pode ser tampering), PostgREST pode aceitar expressão maliciosa. O mesmo em `portal/src/lib/clearing.ts:240-242`.
## Risco / Impacto

PostgREST `.or()` é parseado do lado servidor; se a string contém `)` ou `,`, pode quebrar semântica e retornar dados de outros grupos. Supabase sanitiza na maioria dos casos, mas não é garantido em todas as versões.

## Correção proposta

Validar UUID no TypeScript antes de compor a query:
  ```typescript
  import { z } from "zod";
  const isUuid = z.string().uuid().safeParse(groupId).success;
  if (!isUuid) throw new Error("Invalid group id");
  ```
  E trocar `.or()` por duas queries separadas com UNION via RPC se possível.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.50]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.50).