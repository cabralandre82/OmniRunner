---
id: L09-11
audit_ref: "9.11"
lens: 9
title: "Cessão de crédito implícita em clearing_settlements — documentar"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "migration"]
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
# [L09-11] Cessão de crédito implícita em clearing_settlements — documentar
> **Lente:** 9 — CRO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `settle_clearing` move saldo de debtor → creditor. Sob certa interpretação, é **cessão de crédito** (Art. 286 CC) sem instrumento formal de cessão. Para valores altos, exige registro em cartório ou aditivo contratual.
## Correção proposta

— Contratualmente, clearing é serviço acessório do produto (não cessão): documentar no termo de adesão. Alternativa: emitir recibo eletrônico de liquidação a cada `settle_clearing` em PDF assinado digitalmente.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.11).