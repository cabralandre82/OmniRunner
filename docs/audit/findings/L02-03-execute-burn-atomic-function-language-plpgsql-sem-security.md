---
id: L02-03
audit_ref: "2.3"
lens: 2
title: "execute_burn_atomic — Function LANGUAGE plpgsql sem SECURITY DEFINER vs. chamadas a funções SECURITY DEFINER"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "rls"]
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
# [L02-03] execute_burn_atomic — Function LANGUAGE plpgsql sem SECURITY DEFINER vs. chamadas a funções SECURITY DEFINER
> **Lente:** 2 — CTO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`execute_burn_atomic` em `20260228160001:80` não é `SECURITY DEFINER`. Mas chama `custody_release_committed` e `settle_clearing` que são `SECURITY DEFINER`. Funciona porque o caller é `service_role`, mas em RLS-strict callers os role context muda. Misturar DEFINER/INVOKER é difícil de raciocinar.
## Correção proposta

Marcar `execute_burn_atomic` também como `SECURITY DEFINER` com `SET search_path = public, pg_temp` e conceder `GRANT EXECUTE` apenas a `service_role`. Já existe grant na linha 199.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.3).