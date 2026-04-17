---
id: L16-04
audit_ref: "16.4"
lens: 16
title: "Sem outbound webhooks para parceiros"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["webhook", "integration", "migration", "cron"]
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
# [L16-04] Sem outbound webhooks para parceiros
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Sistema recebe webhooks (Stripe/MP/Asaas/Strava), mas não **emite**. Parceiro B2B que quer receber "quando atleta do meu clube completa corrida, me avise" não tem canal.
## Correção proposta

—

```sql
CREATE TABLE public.outbound_webhooks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL,
  url text NOT NULL,
  secret text NOT NULL,  -- signed HMAC
  events text[] NOT NULL,  -- 'session.verified','coin.distributed','championship.ended'
  enabled boolean DEFAULT true,
  last_delivery_at timestamptz,
  last_delivery_status int,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE public.webhook_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id uuid REFERENCES outbound_webhooks(id),
  event text NOT NULL,
  payload jsonb NOT NULL,
  status_code int,
  attempt int DEFAULT 1,
  next_retry_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz DEFAULT now()
);
```

Cron `*/1 * * * *` processa `webhook_deliveries` onde `status_code != 200 AND attempt < 5` com backoff.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.4).