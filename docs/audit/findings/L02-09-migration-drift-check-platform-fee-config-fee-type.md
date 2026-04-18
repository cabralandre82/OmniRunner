---
id: L02-09
audit_ref: "2.9"
lens: 2
title: "Migration drift — CHECK platform_fee_config.fee_type (duplica 1.44)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "migration", "duplicate"]
files:
  - supabase/migrations/20260417130000_fix_platform_fee_config_check.sql
  - supabase/migrations/20260228170000_custody_gaps.sql
  - tools/integration_tests.ts
correction_type: migration
test_required: true
tests:
  - tools/integration_tests.ts
linked_issues: []
linked_prs:
  - "commit:f62de86"
owner: platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: L01-44
deferred_to_wave: null
note: |
  Duplicata exata de **L01-44** (mesmo achado pela lente CTO). O
  texto do título admite explicitamente: "duplica 1.44". A correção
  em commit `f62de86` (Onda 0) — nova migration canônica
  `20260417130000_fix_platform_fee_config_check.sql` que altera o
  CHECK de `platform_fee_config.fee_type` para incluir `fx_spread`,
  edição forward-compat em `20260228170000_custody_gaps.sql`, mais 2
  testes de integração — fecha L02-09 sem trabalho adicional.

  Marcado como `duplicate_of: L01-44` para que SCORECARD não
  contabilize esforço duplicado.
---
# [L02-09] Migration drift — CHECK platform_fee_config.fee_type (duplica 1.44)
> **Lente:** 2 — CTO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
_(sem descrição detalhada — ver relatório original em `docs/audit/parts/`)_
## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.9).