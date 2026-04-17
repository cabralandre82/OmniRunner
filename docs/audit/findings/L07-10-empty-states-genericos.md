---
id: L07-10
audit_ref: "7.10"
lens: 7
title: "Empty states genéricos"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["ux"]
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
# [L07-10] Empty states genéricos
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Páginas "Sem challenges ativos" mostram texto mas não sugerem próximo passo. Boas UX: "Você não tem challenges. [Criar novo] ou [Aceitar convite]".
## Correção proposta

— Component `<EmptyState title action1 action2 illustration />` reaproveitado.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.10).