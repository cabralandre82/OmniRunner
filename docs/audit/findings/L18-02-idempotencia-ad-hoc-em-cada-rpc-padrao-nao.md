---
id: L18-02
audit_ref: "18.2"
lens: 18
title: "Idempotência ad-hoc em cada RPC — padrão não unificado"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "idempotency", "atomicity", "portal", "migration", "performance"]
files:
  - supabase/migrations/20260419120000_l18_idempotency_keys_unified.sql
  - portal/src/lib/api/idempotency.ts
  - portal/src/lib/api/idempotency.test.ts
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/app/api/distribute-coins/route.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/api/idempotency.test.ts
  - portal/src/app/api/custody/withdraw/route.test.ts
  - portal/src/app/api/distribute-coins/route.test.ts
  - tools/test_l18_idempotency.ts
linked_issues: []
linked_prs:
  - "commit:1f14fbd..HEAD"
owner: backend
runbook: docs/runbooks/IDEMPOTENCY_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed by introducing `public.idempotency_keys` (PK `(namespace,
  actor_id, key)`) plus three RPCs `fn_idem_begin / fn_idem_finalize
  / fn_idem_release` and a GC sweep `fn_idem_gc_safe` cron'd hourly
  via the L12-03 cron-health pattern (`cron_run_state` observability,
  advisory-lock guarded, `lock_timeout`).

  The portal-side wrapper `withIdempotency` (`portal/src/lib/api/
  idempotency.ts`) layers this in front of route handlers: it
  validates `x-idempotency-key`, hashes the canonicalised request
  body (key-sorted JSON), claims the slot, executes the handler at
  most once, finalises or releases on completion/failure, and replays
  the byte-identical cached response on retry. Mismatched body for
  the same key returns `409 IDEMPOTENCY_KEY_CONFLICT` BEFORE any
  mutation runs.

  Retrofitted high-risk endpoints:
   - `/api/custody/withdraw` — `required: true` (header mandatory;
     `400 IDEMPOTENCY_KEY_REQUIRED` otherwise). Highest-risk money-
     out path; closes the gap audited in 18.2.
   - `/api/distribute-coins` — defense-in-depth: keeps the existing
     `coin_ledger.ref_id` UNIQUE for at-most-once mutation AND adds
     RESPONSE replay so a network blip on the response no longer
     re-fires `auditLog` / RPC roundtrips.
   - Swap (`/api/swap`) deferred to a follow-up because each branch
     (create/accept/cancel) carries its own audit trail; tracked in
     ROADMAP but not blocking 18.2 closure.

  Latent bug discovered while writing the integration tests: the
  prior `confirm_custody_deposit` pattern (UNIQUE on resource table)
  could not replay the original HTTP response — only the resource
  id. The new wrapper closes that gap.

  Tests: 22 integration assertions in `tools/test_l18_idempotency.ts`
  (schema, begin lifecycle, finalize, release, GC, cron seed) +
  24 unit tests in `portal/src/lib/api/idempotency.test.ts` (regex,
  canonicalisation, replay/mismatch/release wrapper behaviour) +
  4 new regression tests across the two retrofitted route suites.
  Full portal suite: 1078 passed, 0 failed.
---
# [L18-02] Idempotência ad-hoc em cada RPC — padrão não unificado
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** fixed
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