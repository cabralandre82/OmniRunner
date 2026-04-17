---
id: L18-03
audit_ref: "18.3"
lens: 18
title: "SECURITY DEFINER sem SET search_path em funções antigas"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "migration"]
files: []
correction_type: config
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L18-03] SECURITY DEFINER sem SET search_path em funções antigas
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `fn_delete_user_data` em `20260312000000_fix_broken_functions.sql:5-10` — tem `SET search_path = public`. Mas muitas outras funções criadas em migrations mais antigas (`execute_burn_atomic` em `20260228160001`) não têm.
## Risco / Impacto

— Search-path injection: atacante com acesso a criar schema `attacker_schema` (qualquer user autenticado pode `CREATE SCHEMA` se não revogado) cria função `coin_ledger` nesse schema; se a função SECURITY DEFINER não fixa `search_path`, pode chamar função errada.

## Correção proposta

— Migration de hardening:

```sql
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.proname, n.nspname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef = true
      AND NOT EXISTS (
        SELECT 1 FROM pg_db_role_setting s
        WHERE s.setconfig::text LIKE '%search_path=%'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public, pg_temp',
                   r.proname, r.args);
  END LOOP;
END $$;

-- Also revoke CREATE on public from PUBLIC
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Migration `20260322500000_medium_severity_fixes.sql:66` já faz para algumas — auditar cobertura total.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.3).