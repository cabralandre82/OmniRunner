---
id: L05-03
audit_ref: "5.3"
lens: 5
title: "POST /api/distribute-coins: amount max 1000 — conflita com grandes clubes"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "portal", "ux", "scalability"]
files:
  - portal/src/lib/schemas.ts
  - supabase/migrations/20260421120000_l05_distribute_coins_batch.sql
  - portal/src/app/api/distribute-coins/batch/route.ts
  - portal/src/app/api/v1/distribute-coins/batch/route.ts
  - portal/src/app/api/distribute-coins/route.ts
  - portal/src/lib/openapi/routes/v1-financial.ts
  - portal/public/openapi.json
  - portal/public/openapi-v1.json
  - docs/PORTAL_API.md
correction_type: process
test_required: true
tests:
  - portal/src/lib/schemas.test.ts
  - portal/src/app/api/distribute-coins/route.test.ts
  - portal/src/app/api/distribute-coins/batch/route.test.ts
  - portal/src/app/api/v1/v1-aliases.test.ts
  - tools/test_l05_03_distribute_coins_batch.ts
linked_issues: []
linked_prs:
  - "3f350e5"
owner: unassigned
runbook: docs/runbooks/CUSTODY_INCIDENT_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Two-front fix:
  (1) Per-call cap of /api/distribute-coins raised 1.000 → 100.000 (Zod
      DISTRIBUTE_COINS_AMOUNT_MAX). The custódia + inventory CHECKs at the
      DB layer remain the source of truth for "can we afford?". This alone
      removes the artificial chunking pressure for medium clubs.
  (2) New POST /api/distribute-coins/batch (and v1 alias) accepts up to 200
      atletas in a single SQL transaction via distribute_coins_batch_atomic
      (migration 20260421120000_l05_distribute_coins_batch.sql). Total
      capped at 1MM coins/batch, per-item at 100k, deterministic ref_id
      derivation `<batch>__<idx>` for safe replays. Any item failure
      (CUSTODY_FAILED, INVENTORY_INSUFFICIENT, INVALID_ITEM) rolls back
      the entire batch — closes the residual atomicity surface still
      visible to clients that previously looped /api/distribute-coins.

  Drive-by fix bundled in the same migration: L19-01 had introduced a
  latent ambiguity bug in emit_coins_atomic (`SELECT ledger_id FROM
  coin_ledger_idempotency` collided with the OUT parameter named
  `ledger_id`), causing 42702 on every PG-context invocation. The column
  is now qualified `cli.ledger_id` so SQL contexts (including the new
  batch loop) work correctly.
---
# [L05-03] POST /api/distribute-coins: amount max 1000 — conflita com grandes clubes
> **Lente:** 5 — CPO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/lib/schemas.ts` distributeCoinsSchema: `amount: z.number().int().min(1).max(1000)`. Um clube com 500 atletas distribuindo 10 moedas por semana faz **5.000 moedas** de uma vez — bloqueado.
## Risco / Impacto

— Coach precisa fazer 5 chamadas sequenciais → multiplica risco de atomicidade (já CRITICAL [2.1]) e degrada UX.

## Correção proposta

— Aumentar para `max(100_000)` e adicionar variante `POST /api/distribute-coins/batch` aceitando `array<{athlete_id, amount}>` e fazendo todas as operações em **uma transação SQL** via nova RPC `distribute_coins_batch_atomic`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.3).