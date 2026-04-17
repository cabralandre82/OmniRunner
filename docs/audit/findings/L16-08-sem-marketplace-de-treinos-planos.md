---
id: L16-08
audit_ref: "16.8"
lens: 16
title: "Sem marketplace de treinos/planos"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["migration"]
files: []
correction_type: code
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
# [L16-08] Sem marketplace de treinos/planos
> **Lente:** 16 — CAO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `training-plan` module existe (1500+ linhas de migration). Mas não há "comprar plano de maratona do Coach X" entre grupos.
## Correção proposta

— `plan_listings` table + checkout com `platform_revenue` recebendo taxa de marketplace.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.8).