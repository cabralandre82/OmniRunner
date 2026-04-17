---
id: L07-12
audit_ref: "7.12"
lens: 7
title: "Copy financeiro confunde atleta"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "mobile"]
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
# [L07-12] Copy financeiro confunde atleta
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— UI usa "Coins", "Badges", "Créditos", "Inventário" — quatro nomes para conceitos próximos. Atleta não entende diferença entre "moedas no wallet" e "badges de conquista".
## Correção proposta

— Glossário visual + tooltip em cada contexto: "Moedas: usadas para pagar prêmios. Badges: conquistas não-monetárias."

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.12).