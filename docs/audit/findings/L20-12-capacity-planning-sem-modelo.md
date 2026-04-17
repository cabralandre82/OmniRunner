---
id: L20-12
audit_ref: "20.12"
lens: 20
title: "Capacity planning sem modelo"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile"]
files:
  - docs/CAPACITY_PLANNING.md
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
# [L20-12] Capacity planning sem modelo
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Quando escalar Supabase (db.micro → db.small)? Quando atingir quantos usuários? Sem projeção documentada.
## Correção proposta

— `docs/CAPACITY_PLANNING.md` com curva: MAU × requests/MAU/mo × queries/request × cost/query → recomendação de tier Supabase para MAU = 10k, 50k, 200k.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.12).