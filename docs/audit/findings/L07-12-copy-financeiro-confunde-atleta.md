---
id: L07-12
audit_ref: "7.12"
lens: 7
title: "Copy financeiro confunde atleta"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "ux", "design-system"]
files:
  - docs/design/UX_BASELINE.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: design+frontend
runbook: docs/design/UX_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Coberto pelo `docs/design/UX_BASELINE.md` §L07-12: glossário canônico OmniCoins / Badges / Créditos / (deprecated) Inventário, com `<TermDef>` tooltip na primeira ocorrência por tela linkando `/help/glossary`. Modelo de dados (`coaching_groups.token_inventory`) intocado — só labels mudam. Implementação Wave 3.
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