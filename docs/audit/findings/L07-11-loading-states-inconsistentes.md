---
id: L07-11
audit_ref: "7.11"
lens: 7
title: "Loading states inconsistentes"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "portal", "ux", "design-system"]
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
  Coberto pelo `docs/design/UX_BASELINE.md` §L07-11: regra `<SkeletonCard rows={page_size} />` para listas, `<SkeletonDetail />` para single-record (mesmo grid → zero CLS), spinner-in-button para mutations. Mirror Flutter via `shimmer` package. Implementação Wave 3.
---
# [L07-11] Loading states inconsistentes
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Algumas listas mostram skeleton, outras spinner, outras branco. Mesma tela entre mobile/web. Coerência.
## Correção proposta

— Design system: todas as listas usam `<SkeletonCard rows={5} />`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.11).