---
id: L18-02
audit_ref: "18.2"
lens: 18
title: "Idempotência ad-hoc em cada RPC — padrão não unificado"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "idempotency", "atomicity", "portal", "migration", "performance"]
files: []
correction_type: code
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
# [L18-02] Idempotência ad-hoc em cada RPC — padrão não unificado
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `confirm_custody_deposit` usa `FOR UPDATE` + status check. `execute_burn_atomic` usa `FOR UPDATE` no wallet. `execute_swap` usa UUID ordering. `execute_withdrawal` NÃO tem idempotency. `distribute-coins` (JS) NÃO tem. Padrão diferente em cada função.
## Risco / Impacto

— Duas chamadas concorrentes do mesmo `withdraw` via retry de Vercel edge → duas execuções.

## Correção proposta

— Pattern de idempotency key server-side:

```sql
CREATE TABLE public.idempotency_keys (
  key text PRIMARY KEY,
  request_hash bytea NOT NULL,
  response jsonb,
  status_code int,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '24 hours')
);

CREATE INDEX idx_idem_expires ON idempotency_keys(expires_at);

CREATE OR REPLACE FUNCTION public.fn_idem_check_or_store(
  p_key text, p_request_hash bytea
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_existing jsonb;
BEGIN
  SELECT jsonb_build_object(
    'found', true, 'response', response, 'status_code', status_code,
    'hash_match', request_hash = p_request_hash
  ) INTO v_existing
  FROM idempotency_keys WHERE key = p_key AND expires_at > now() FOR UPDATE;

  IF FOUND THEN RETURN v_existing; END IF;

  INSERT INTO idempotency_keys(key, request_hash) VALUES (p_key, p_request_hash);
  RETURN jsonb_build_object('found', false);
END;$$;
```

Middleware API consulta antes de executar; store após. Cobre ambos RPC e Route Handler.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.2).