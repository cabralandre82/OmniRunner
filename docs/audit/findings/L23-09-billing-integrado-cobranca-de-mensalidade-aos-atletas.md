---
id: L23-09
audit_ref: "23.9"
lens: 23
title: "Billing integrado (cobrança de mensalidade aos atletas)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "ux", "reliability", "personas", "coach"]
files: []
correction_type: process
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
# [L23-09] Billing integrado (cobrança de mensalidade aos atletas)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `billing` module + Asaas existem. Coach consegue cobrar atletas via produto? Fluxo Asaas → custódia ([9.8]) → pagamento de staff? Ciclo inteiro de ROI não auditado.
## Correção proposta

— E2E: atleta paga R$ 200 via Asaas → vira coins na custody da assessoria → coach distribui moedas como bônus → saca via withdraw. Se não existe, é **oportunidade gigante** perdida.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.9).