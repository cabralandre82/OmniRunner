---
id: L07-10
audit_ref: "7.10"
lens: 7
title: "Empty states genéricos"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["ux", "design-system"]
files:
  - docs/design/UX_BASELINE.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 9a74988

owner: design+frontend
runbook: docs/design/UX_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Coberto pelo `docs/design/UX_BASELINE.md` §L07-10: componente canônico `<EmptyState illustration title description primaryAction secondaryAction />`. Inventário de 8 telas in-scope listado no doc. Implementação Wave 3.
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