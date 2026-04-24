---
id: L07-07
audit_ref: "7.7"
lens: 7
title: "Ícones sem fallback (mobile offline)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["rls", "reliability", "mobile", "ux"]
files:
  - docs/design/UX_BASELINE.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: design+frontend
runbook: docs/design/UX_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Coberto pelo `docs/design/UX_BASELINE.md` §L07-07: `cached_network_image` obrigatório, placeholder = iniciais coloridas determinísticas, fallback de erro persistente com badge `!`, cache 30d/100MB. Implementação Wave 3 dentro da PR-series do design system.
---
# [L07-07] Ícones sem fallback (mobile offline)
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Se atleta está offline, avatares de grupo (URLs Supabase Storage) falham e mostram ícone padrão; mas não há placeholder de blur-hash ou cache agressivo.
## Correção proposta

— `cached_network_image` (já usado?) com `placeholder` = iniciais do grupo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.7).