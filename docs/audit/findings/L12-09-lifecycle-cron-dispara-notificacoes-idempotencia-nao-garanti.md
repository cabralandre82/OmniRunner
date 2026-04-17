---
id: L12-09
audit_ref: "12.9"
lens: 12
title: "lifecycle-cron dispara notificações idempotência não garantida"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["migration"]
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
# [L12-09] lifecycle-cron dispara notificações idempotência não garantida
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `*/5 * * * *` sem tabela `sent_notifications` dedicada.
## Correção proposta

—

```sql
CREATE TABLE notification_log (
  user_id uuid, notification_code text, ref_id text,
  sent_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, notification_code, ref_id)
);
-- Before sending:
INSERT INTO notification_log VALUES (uid, 'streak_broken', today::text)
  ON CONFLICT DO NOTHING;
IF NOT FOUND THEN RETURN; END IF;  -- already sent
-- send push
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.9).