---
id: L09-01
audit_ref: "9.1"
lens: 9
title: "Modelo de \"Coin = US$ 1\" pode ser classificado como arranjo de pagamento (BCB Circ. 3.885/2018)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "testing", "reliability"]
files:
  - docs/compliance/BCB_CLASSIFICATION.md
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
# [L09-01] Modelo de "Coin = US$ 1" pode ser classificado como arranjo de pagamento (BCB Circ. 3.885/2018)
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— O produto emite tokens resgatáveis por reais/dólares (via withdrawal com `fx_rate`) e permite transferência entre grupos (`swap_orders`). Sem tabela `kyc_verifications`, sem limite por CPF/CNPJ, sem integração com COAF, sem relatório de operações suspeitas (SOS).

- Emissor ≠ banco, mas está **armazenando valor em nome de terceiros** (`custody_accounts`) e disponibilizando liquidação entre terceiros (`clearing_settlements`, `execute_swap`).
- Volume potencial > R$ 500 mi/ano × > 1 M transações aciona critério BCB para autorização de IP (Instituição de Pagamento — Resolução BCB 80/2021).
## Risco / Impacto

— Operação sem autorização = intervenção BCB + sanção penal Art. 16 Lei 7.492/86 ("operação não autorizada de instituição financeira" — reclusão 1–4 anos).

## Correção proposta

— Opções excludentes:

1. **Restringir produto a "crédito de marketing"** não-resgatável (sem withdrawal em dinheiro) → sai do perímetro BCB, vira vale-benefício.
2. **Parceria com IP autorizada** (ex.: Asaas já citado no código tem autorização de conta escrow). Plataforma vira Payment Initiation Service (PIS) — custódia roda na IP parceira, código apenas orquestra.
3. **Obter autorização BCB como IP** (prazo realista 18–24 meses, capital mínimo R$ 2 mi, estrutura de compliance, diretor estatutário).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.1).