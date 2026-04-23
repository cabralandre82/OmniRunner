---
id: L07-05
audit_ref: "7.5"
lens: 7
title: "Portal sem acessibilidade (a11y) declarada"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "portal", "a11y"]
files:
  - docs/a11y.md
  - portal/.eslintrc.json
  - tools/audit/a11y-baseline-allowlist.json
  - tools/audit/check-a11y-baseline.ts
correction_type: process
test_required: true
tests:
  - npm run audit:a11y-baseline
linked_issues: []
linked_prs:
  - local:906fc19
  - local:78c8268
owner: platform-portal
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Shipped a WCAG 2.1 AA baseline document at `docs/a11y.md` citing
  LBI 13.146/2015, extended `portal/.eslintrc.json` with
  `plugin:jsx-a11y/recommended` and pinned the 10 critical rules
  to "error". Two ratchet allow-lists keep the CI guard truthful
  without blocking merges on legacy code: (a)
  `tools/audit/a11y-baseline-allowlist.json` enumerates the 38
  existing `<table>` offenders without `<caption>`; (b) an
  `overrides` block in `.eslintrc.json` downgrades the four rules
  that fire in 21 legacy files to "warn" while keeping "error"
  for new code. The guard flags stale allow-list entries so the
  ratchet does not rot. 27 static invariants enforced via
  `npm run audit:a11y-baseline`.
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