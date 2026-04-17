---
id: L05-03
audit_ref: "5.3"
lens: 5
title: "POST /api/distribute-coins: amount max 1000 — conflita com grandes clubes"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "portal", "ux"]
files:
  - portal/src/lib/schemas.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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