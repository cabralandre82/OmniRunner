---
id: L23-19
audit_ref: "23.19"
lens: 23
title: "Múltiplos clubes (coach atende em 3 clubes)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["personas", "coach"]
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
# [L23-19] Múltiplos clubes (coach atende em 3 clubes)
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `coaching_members` 1:N, mas UI esconde bem? Coach com 3 clubes troca grupo via `select-group`. Cada troca exige recarga completa.
## Correção proposta

— Dashboard multi-clube agregado "Meu dia em todos os clubes".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.19).