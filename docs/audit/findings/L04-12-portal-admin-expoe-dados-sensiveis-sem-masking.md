---
id: L04-12
audit_ref: "4.12"
lens: 4
title: "Portal admin expõe dados sensíveis sem masking"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
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
# [L04-12] Portal admin expõe dados sensíveis sem masking
> **Lente:** 4 — CLO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/(portal)/platform/**` exibe CPF, nome completo de atletas em tabelas. Não há view com CPF mascarado (`123.***.***-45`).
## Correção proposta

— Component `<MaskedDoc value={cpf} revealOnClick={hasPermission('view_pii')} />` + audit_log a cada reveal.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.12).