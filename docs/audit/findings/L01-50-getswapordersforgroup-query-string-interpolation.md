---
id: L01-50
audit_ref: "1.50"
lens: 1
title: "getSwapOrdersForGroup — Query string interpolation"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "security-headers", "integration", "mobile", "portal"]
files:
  - portal/src/lib/swap.ts
  - portal/src/lib/clearing.ts
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