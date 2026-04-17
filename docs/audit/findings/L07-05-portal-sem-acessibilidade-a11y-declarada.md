---
id: L07-05
audit_ref: "7.5"
lens: 7
title: "Portal sem acessibilidade (a11y) declarada"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "portal", "a11y"]
files:
  - docs/a11y.md
correction_type: process
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
# [L07-05] Portal sem acessibilidade (a11y) declarada
> **Lente:** 7 — CXO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep -r "aria-" portal/src --include="*.tsx"` retorna ~70 matches mas auditoria superficial: botões principais de custódia (`Distribuir`, `Aceitar swap`) não têm `aria-label` quando só há ícone, `<table>` sem `<caption>`, nenhum `role="alert"` nos toasts.
## Risco / Impacto

— Lei Brasileira de Inclusão (LBI 13.146/2015). Demandas judiciais de acessibilidade crescem 30% a.a.

## Correção proposta

—

1. Rodar `axe-core` CI em páginas principais.
2. Adicionar `eslint-plugin-jsx-a11y`.
3. Documentar WCAG 2.1 AA como objetivo em `docs/a11y.md`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.5).