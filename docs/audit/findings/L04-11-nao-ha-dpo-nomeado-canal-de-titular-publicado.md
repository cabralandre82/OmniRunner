---
id: L04-11
audit_ref: "4.11"
lens: 4
title: "Não há DPO nomeado / canal de titular publicado"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["lgpd", "mobile", "portal"]
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
# [L04-11] Não há DPO nomeado / canal de titular publicado
> **Lente:** 4 — CLO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/(portal)/help/help-center-content.tsx` menciona FAQ mas não há endpoint/email dedicado `dpo@omnirunner.com`. LGPD Art. 41.
## Correção proposta

— Página `/privacy/dpo` com: nome do encarregado, email, telefone, prazo de resposta (15 dias).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.11).