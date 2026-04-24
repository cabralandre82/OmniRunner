---
id: L02-03
audit_ref: "2.3"
lens: 2
title: "execute_burn_atomic — Function LANGUAGE plpgsql sem SECURITY DEFINER vs. chamadas a funções SECURITY DEFINER"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "atomicity", "rls", "fixed", "duplicate"]
files:
  - supabase/migrations/20260417140000_execute_burn_atomic_hardening.sql
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - aa816fb
  - 8c62f60
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: L02-02
deferred_to_wave: null
note: |
  K2 batch — closed as covered by L02-02 fix. Migration
  20260417140000_execute_burn_atomic_hardening.sql line 119 already
  declares `execute_burn_atomic` as `SECURITY DEFINER` with
  `SET search_path = public, pg_temp` and `SET lock_timeout = '2s'`.
  GRANT EXECUTE is restricted to service_role (line 284). The proposed
  correction in this finding is therefore satisfied; tracking as
  duplicate_of L02-02 to keep the registry clean.
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