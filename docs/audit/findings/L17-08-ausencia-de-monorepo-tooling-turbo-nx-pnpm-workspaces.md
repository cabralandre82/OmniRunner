---
id: L17-08
audit_ref: "17.8"
lens: 17
title: "Ausência de monorepo tooling (turbo, nx, pnpm-workspaces)"
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