---
id: L11-07
audit_ref: "11.7"
lens: 11
title: "sqlcipher_flutter_libs: ^0.7.0+eol — \"eol\" = end of life"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "reliability"]
files: []
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
# [L11-07] sqlcipher_flutter_libs: ^0.7.0+eol — "eol" = end of life
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linha do pubspec explicitamente marca EOL. Código cripta banco local mas depende de biblioteca sem manutenção.
## Risco / Impacto

— CVE futuro em sqlcipher não será corrigido; app exposto.

## Correção proposta

— Migrar para `drift` encrypted (`drift/drift_sqlflite` + encryption plugin) ou `sqlite3_flutter_libs` + `sqlcipher-mozilla` fork mantido.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.7).