---
id: L09-05
audit_ref: "9.5"
lens: 9
title: "IOF não recolhido em swap inter-cliente"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile"]
files: []
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
# [L09-05] IOF não recolhido em swap inter-cliente
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `execute_swap` transfere valor entre CNPJs distintos mediante taxa. Dependendo da natureza legal (crédito de marketing vs. direitos creditórios vs. ativo), pode incidir IOF (0,38 % genérico). Código não calcula nem segrega.
## Risco / Impacto

— Autuação Receita com juros desde a primeira operação.

## Correção proposta

— Consulta prévia com tributarista; se aplicável, nova coluna `iof_amount` em `swap_orders` + recolhimento mensal DARF.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.5).