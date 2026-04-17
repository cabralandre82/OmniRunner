---
id: L23-11
audit_ref: "23.11"
lens: 23
title: "Relatórios para atleta (resumo mensal do coach)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "personas", "coach"]
files: []
correction_type: config
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
# [L23-11] Relatórios para atleta (resumo mensal do coach)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach gasta 1h/mês por atleta escrevendo resumo no Google Docs → envia PDF pelo WhatsApp. Produto não automatiza.
## Correção proposta

— `/api/coaching/athlete-monthly-report?user_id&month` gera PDF: volume, evolução pace, pontos fortes, áreas de melhoria, palavra do coach (campo texto editável). Coach revisa + aprova + envia.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.11).