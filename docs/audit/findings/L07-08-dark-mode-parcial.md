---
id: L07-08
audit_ref: "7.8"
lens: 7
title: "Dark mode parcial"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal"]
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