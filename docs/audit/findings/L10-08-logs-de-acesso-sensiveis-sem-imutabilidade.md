---
id: L10-08
audit_ref: "10.8"
lens: 10
title: "Logs de acesso sensíveis sem imutabilidade"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: []
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
# [L10-08] Logs de acesso sensíveis sem imutabilidade
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `audit_logs` é tabela normal; atacante com service-role pode `DELETE`/`UPDATE`.
## Correção proposta

—

1. Role `audit_read_only` com `GRANT SELECT` apenas.
2. Trigger `BEFORE DELETE OR UPDATE ON audit_logs` que bloqueia operações.
3. Export incremental para S3 com Object Lock (compliance mode) — 7 anos.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.8).