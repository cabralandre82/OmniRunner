---
id: L01-04
audit_ref: "1.4"
lens: 1
title: "POST /api/custody (create deposit / confirm) — Sem idempotency-key"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "idempotency", "webhook", "security-headers", "mobile", "portal"]
files:
  - portal/src/app/api/custody/route.ts
  - portal/src/app/api/custody/route.test.ts
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
# [L01-04] POST /api/custody (create deposit / confirm) — Sem idempotency-key
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Assessoria (admin_master)
## Achado
`portal/src/app/api/custody/route.ts:60-146` cria depósito sem `idempotency-key` do cliente. Double-click cria dois registros `custody_deposits` PENDING.
  - A coluna `UNIQUE` em `payment_reference` (migration `20260228170000_custody_gaps.sql:33`) é **parcial `WHERE payment_reference IS NOT NULL`** — portanto não protege depósitos enquanto o reference é `NULL` (antes do gateway retornar).
  - `confirmDeposit(depositId)` chamado sem verificação de ownership (embora use `SECURITY DEFINER`, não recebe `group_id` do caller para cross-check).
## Risco / Impacto

Um admin_master pode, com conluio, chamar `confirm_custody_deposit` via RPC directa (se tiver acesso) e creditar sem pagar (verificar se a RPC confirma sem verificar gateway). Mais realista: duplicação cria UX ruim e possíveis dois checkouts pendentes abandonados.

## Correção proposta

Exigir header `x-idempotency-key` no POST de deposit; criar `deposit_idempotency` table ou reutilizar `custody_deposits.idempotency_key` com UNIQUE.
  - Em `confirmDeposit`, alterar signature para `confirmDeposit(depositId, groupId)` e validar em SQL: `WHERE id=p_deposit_id AND group_id=p_group_id`.

## Teste de regressão

`portal/src/app/api/custody/route.test.ts` — dois POSTs com mesmo idempotency-key devem retornar o mesmo deposit_id.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.4).