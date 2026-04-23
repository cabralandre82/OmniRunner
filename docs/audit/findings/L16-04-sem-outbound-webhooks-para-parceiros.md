---
id: L16-04
audit_ref: "16.4"
lens: 16
title: "Sem outbound webhooks para parceiros"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["webhook", "integration", "migration", "cron"]
files:
  - supabase/migrations/20260421610000_l16_04_outbound_webhooks.sql
  - tools/audit/check-outbound-webhooks.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-outbound-webhooks.ts
linked_issues: []
linked_prs:
  - "local:48cd3c4"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in 48cd3c4 (J28). `fn_validate_webhook_url` (IMMUTABLE
  PARALLEL SAFE) blocks non-HTTPS, loopback/localhost,
  RFC1918 (10/8, 172.16/12, 192.168/16), link-local,
  100.64/10, 0.0.0.0, and 169.254/16 targets — preventing
  attackers from pivoting our egress into the cluster.
  `fn_validate_outbound_webhook_events` whitelists 15
  canonical events (session.verified, coin.distributed,
  championship.ended, athlete.enrolled, sponsorship.activated
  …) so partners can't be leaked undocumented internal
  signals. `public.outbound_webhook_endpoints` stores
  configuration (HMAC secret, event filter, enabled flag,
  per-endpoint rate limit) with RLS for group admins.
  `public.outbound_webhook_deliveries` logs every attempt —
  state machine (pending → in_flight → delivered/failed),
  exponential backoff, `FOR UPDATE SKIP LOCKED` so multiple
  workers can claim without duplicates, respects
  `audit_logs_retention_config`. Admin RPCs
  (`fn_outbound_webhook_register`, `_rotate_secret`,
  `_enable`) are SECURITY DEFINER with coaching_members
  role check; worker RPCs (`fn_outbound_webhook_enqueue`,
  `_claim`, `_mark_delivered`, `_mark_failed`) are
  service-role-only. Invariants locked by
  `npm run audit:outbound-webhooks`.
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