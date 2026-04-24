---
id: L07-08
audit_ref: "7.8"
lens: 7
title: "Dark mode parcial"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "ux", "design-system"]
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
  Coberto pelo `docs/design/UX_BASELINE.md` §L07-08: adoção de `next-themes` + Tailwind `dark:` variants (já configurado `darkMode: 'class'`). Mapping completo de semantic tokens. Persistência via cookie `portal_theme` para evitar FOUC em RSC. Implementação Wave 3.
---
# [L07-08] Dark mode parcial
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/core/theme/` tem themes mas auditoria rápida sugere que portal web não tem dark mode. Corredores treinam cedo/tarde — dark mode é esperado.
## Correção proposta

— Adicionar `next-themes` no portal + dark tokens no Tailwind config.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.8).