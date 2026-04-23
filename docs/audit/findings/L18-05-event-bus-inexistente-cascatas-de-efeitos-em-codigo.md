---
id: L18-05
audit_ref: "18.5"
lens: 18
title: "Event bus inexistente — cascatas de efeitos em código imperativo"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["edge-function", "migration"]
files:
  - supabase/migrations/20260421540000_l18_05_outbox_event_bus.sql
  - tools/audit/check-outbox-event-bus.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:b676952
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  Durable outbox primitives replace implicit caller-side
  orchestration with an explicit event queue.
  `public.outbox_events` is append-only with UNIQUE(event_key)
  for idempotent producers, CHECK-bounded status state-machine
  (pending/processing/completed/failed/dead), 15 event_types,
  7 aggregate_types, attempts + backoff + last_error columns,
  4 indexes (ready partial, aggregate composite, type+time,
  dead), RLS admin-only SELECT, and 30-day retention
  registration. Lifecycle RPCs (all SECURITY DEFINER,
  service-role only): `fn_outbox_emit` (ON CONFLICT DO
  NOTHING), `fn_outbox_claim` (FOR UPDATE SKIP LOCKED +
  visibility lease [5s, 3600s], limit [1, 1000]),
  `fn_outbox_complete`, `fn_outbox_fail` (promotes to 'dead'
  past max_attempts, otherwise backoff + re-queue to pending),
  and `fn_outbox_dlq` sweep. AFTER UPDATE OF is_verified
  trigger on `public.sessions` produces `session.verified`
  events using event_key `session.verified:<uuid>` — the
  trigger fails open (RAISE WARNING) so outbox outages never
  block writes. 43-invariant CI guard
  `npm run audit:outbox-event-bus`.
---
# [L18-05] Event bus inexistente — cascatas de efeitos em código imperativo
> **Lente:** 18 — Principal Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Quando um `session` é marcada `is_verified=true`, devem acontecer: compute skill bracket, update leaderboard, compute kpis, check badges, notify coach. Hoje, cada caller orquestra. Se esquecer um, estado fica inconsistente.
## Correção proposta

— Postgres triggers ou NOTIFY/LISTEN:

```sql
CREATE OR REPLACE FUNCTION fn_on_session_verified()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_verified AND OLD.is_verified IS DISTINCT FROM true THEN
    PERFORM pg_notify('session_verified',
      jsonb_build_object('session_id', NEW.id, 'user_id', NEW.user_id)::text);
  END IF;
  RETURN NEW;
END;$$;

CREATE TRIGGER trg_session_verified AFTER UPDATE ON sessions
  FOR EACH ROW EXECUTE FUNCTION fn_on_session_verified();
```

Edge Function "session-events-consumer" consome (com retry, DLQ). Trocou orquestração implícita por explícita.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.5).