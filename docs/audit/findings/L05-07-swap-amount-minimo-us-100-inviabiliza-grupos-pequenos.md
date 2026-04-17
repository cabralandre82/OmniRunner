---
id: L05-07
audit_ref: "5.7"
lens: 5
title: "Swap: amount mínimo US$ 100 inviabiliza grupos pequenos"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/app/api/swap/route.ts
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
# [L05-07] Swap: amount mínimo US$ 100 inviabiliza grupos pequenos
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/swap/route.ts:17` `amount_usd: z.number().min(100)…`. Um clube de 20 atletas que quer swap de US$ 50 não consegue.
## Risco / Impacto

— Adoção limitada nos segmentos amadores. Atletas amadores nunca veem valor no P2P.

## Correção proposta

— `min(10)` e UI destaca "amount mínimo = US$ 10".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.7).