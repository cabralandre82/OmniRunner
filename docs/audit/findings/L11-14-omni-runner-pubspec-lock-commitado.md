---
id: L11-14
audit_ref: "11.14"
lens: 11
title: "omni_runner/pubspec.lock commitado?"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "supply-chain", "fixed"]
files:
  - .gitignore
  - omni_runner/pubspec.lock
  - tools/audit/check-k4-security-fixes.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 99ac6c7
  - 4d7950b
owner: mobile
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — `omni_runner/pubspec.lock` is now committed (was
  ignored). Flutter docs require lockfile commit for application
  packages so every CI run, dev box, and release bundle resolves
  to the same transitive dependency tree. The .gitignore line
  `omni_runner/pubspec.lock` was replaced with an explicit comment
  `# intentionally NOT ignored` to prevent regression. CI guard
  `audit:k4-security-fixes` asserts both the comment marker and
  the file's existence on disk.
---
# [L11-14] omni_runner/pubspec.lock commitado?
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Não verificado. Flutter recomenda commitar para apps.
## Correção proposta

— Confirmar `git ls-files omni_runner/pubspec.lock` existe; se não, adicionar.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.14).