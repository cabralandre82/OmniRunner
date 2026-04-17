---
id: L05-17
audit_ref: "5.17"
lens: 5
title: "Gamificação: badges permanentes sem prazo"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
files: []
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
# [L05-17] Gamificação: badges permanentes sem prazo
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `badge_awards` não tem `expires_at`. "Atleta de bronze 2024" continua para sempre.
## Correção proposta

— Opcional: badges anuais têm `valid_until`, expiram automático.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.17).