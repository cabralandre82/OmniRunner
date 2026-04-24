---
id: L17-08
audit_ref: "17.8"
lens: 17
title: "Ausência de monorepo tooling (turbo, nx, pnpm-workspaces)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: ["portal"]
files:
  - docs/runbooks/MONOREPO_TOOLING_DECISION.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: platform
runbook: docs/runbooks/MONOREPO_TOOLING_DECISION.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Decision ratified in docs/runbooks/MONOREPO_TOOLING_DECISION.md:
  stay on the dual-package layout (portal/ npm + omni_runner/
  pub) until package count >= 3, white-label tenant repo
  appears, or portal CI > 8 min sustained. Mitigations in
  the meantime: top-level audit registry in root package.json,
  parallel CI jobs per concern, copy-and-CI-guard for
  shared types (with the existing test_l08_01_02 +
  audit:event-catalog drift checks), and audit:lockfile-drift
  for shared dependency consistency. Migration path to
  Turborepo (2-3 dev-days, reversible) documented for when
  triggers fire.
---
# [L17-08] Ausência de monorepo tooling (turbo, nx, pnpm-workspaces)
> **Lente:** 17 — VP Eng · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/` e `omni_runner/` coexistem na raiz mas sem gerenciador unificado. Não há `turbo.json`, `nx.json`, `pnpm-workspace.yaml`.
## Correção proposta

— Quando atingir 3+ pacotes (portal, shared-types, partner-sdk), adotar Turborepo com caches de CI remotos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.8).