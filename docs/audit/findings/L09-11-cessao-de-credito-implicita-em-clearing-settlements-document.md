---
id: L09-11
audit_ref: "9.11"
lens: 9
title: "Cessão de crédito implícita em clearing_settlements — documentar"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["finance", "legal", "compensation", "documentation"]
files:
  - docs/legal/CLEARING_NOT_CESSAO_DE_CREDITO.md
  - tools/audit/check-clearing-not-cession.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-clearing-not-cession.ts
linked_issues: []
linked_prs:
  - d894bbc
owner: finance
runbook: docs/legal/CLEARING_NOT_CESSAO_DE_CREDITO.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Documento canônico `docs/legal/CLEARING_NOT_CESSAO_DE_CREDITO.md`
  v1.0 fixa a posição: `settle_clearing` = compensação multilateral
  (CC Art. 368), NÃO cessão de crédito (CC Art. 286). Salvaguardas:
  perímetro fechado (mesma assessoria), cap mensal R$ 100.000,
  recibo eletrônico SHA-256, reconciliação diária, encerramento
  obrigatório antes de saída de membro. Tabela diff vs swap_orders
  (que É cessão, fechada via ADR-008). Review triggers definidos.
  CI guard `audit:clearing-not-cession` (16 asserts).
---
# [L09-11] Cessão de crédito implícita em clearing_settlements
> **Lente:** 9 — CRO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed
**Camada:** Legal / docs

## Achado
`settle_clearing` move saldo entre membros. Sob certa
interpretação seria cessão de crédito (CC Art. 286), o que
exigiria instrumento formal. Faltava posição canônica do
controlador.

## Correção aplicada
Documento canônico em `docs/legal/CLEARING_NOT_CESSAO_DE_CREDITO.md`
v1.0 estabelece: clearing é **compensação multilateral**
(CC Art. 368), não cessão. Salvaguardas operacionais:

1. Perímetro fechado (membros da mesma assessoria).
2. Cap mensal R$ 100.000 por assessoria; acima exige aprovação
   `admin_master`.
3. Termo de Adesão da Assessoria (cl. 4.2) caracteriza serviço
   acessório.
4. Recibo eletrônico SHA-256 em `audit_logs.category='clearing'`.
5. Reconciliação diária `reconcile_clearing_daily`.
6. Encerramento obrigatório antes de saída do membro.

Tabela comparativa vs `swap_orders` (que **é** cessão e está
formalizada via ADR-008). Review triggers definidos (volume
> 1M, cross-assessoria, ANPD/BCB).

CI guard `audit:clearing-not-cession` (16 asserts).

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via doc canônico + CI guard.
