---
id: L18-05
audit_ref: "18.5"
lens: 18
title: "Event bus inexistente — cascatas de efeitos em código imperativo"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["edge-function", "migration"]
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