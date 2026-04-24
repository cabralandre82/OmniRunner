---
id: L17-07
audit_ref: "17.7"
lens: 17
title: "Não há docs/adr/ ativo para decisões arquiteturais"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["adr", "governance", "documentation"]
files:
  - docs/adr/README.md
  - tools/audit/check-adr-governance.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-adr-governance.ts
linked_issues: []
linked_prs:
  - d894bbc
owner: architecture
runbook: docs/adr/README.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  `docs/adr/` já tinha 12 ADRs mas o índice no README listava
  apenas 1. Atualizado para enumerar todos os 12 (chronological)
  + status + audit ref + naming convention (`ADR-NNNN-<slug>.md`)
  + when-to-write/when-not-to + cross-link rules. CI guard
  `audit:adr-governance` (16 asserts) garante que cada ADR file
  é listado no índice e que o naming pattern persiste.
---
# [L17-07] Não há docs/adr/ ativo para decisões arquiteturais
> **Lente:** 17 — VP Eng · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Achado
Pasta `docs/adr/` existia com 12 ADRs mas o `README.md` listava
apenas 1 no índice. Falta de governança visível para futuros
contributors descobrirem decisões existentes.

## Correção aplicada
README atualizado:
- Índice enumera todos 12 ADRs com status e audit-ref.
- Naming convention `ADR-NNNN-<slug>.md` para novos ADRs.
- "When to write an ADR" / "When NOT to write".
- Cross-link rule: cada ADR Accepted deve ser referenciado por
  ≥ 1 código/migration/runbook.

CI guard `audit:adr-governance` (16 asserts) garante que novos
ADRs aparecem no índice e que a naming convention persiste.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via README v2 + CI guard.
