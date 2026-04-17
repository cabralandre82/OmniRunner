---
id: L16-01
audit_ref: "16.1"
lens: 16
title: "Sem white-label / branding customizado por grupo"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal", "migration"]
files: []
correction_type: code
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
# [L16-01] Sem white-label / branding customizado por grupo
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/branding/` existe mas auditoria rápida sugere mínimo. Grupo grande (ex.: "Corredores do Morumbi" com 3000 atletas) quer app com cor/logo próprios no mobile.
## Correção proposta

— `ALTER TABLE coaching_groups ADD COLUMN branding jsonb` com `{primary_color, logo_url, custom_domain}`. Flutter lê via `group_details` endpoint e aplica no ThemeData. Portal aplica via CSS var.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.1).