---
id: L16-03
audit_ref: "16.3"
lens: 16
title: "Sem API pública para parceiros B2B"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "rate-limit", "security-headers", "integration", "portal", "migration"]
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
# [L16-03] Sem API pública para parceiros B2B
> **Lente:** 16 — CAO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Grep `api_key|api_keys|partner_api` → zero tabelas. Expansão B2B exige integração com:

- Strava (já existe — como parceiro Omni)
- Garmin Connect
- Polar Flow
- Suunto
- Marca esportiva X para campanha conjunta
- ERP/CRM do cliente (assessoria grande com RD Station)
## Risco / Impacto

— Bloqueio de parcerias estratégicas = limite de receita B2B.

## Correção proposta

—

```sql
CREATE TABLE public.api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key_prefix text NOT NULL UNIQUE,  -- "or_live_XXXX" (first 8 chars visible)
  key_hash bytea NOT NULL,  -- SHA-256 of the full key
  group_id uuid REFERENCES coaching_groups(id),
  partner_name text,
  scopes text[] NOT NULL DEFAULT '{}',  -- 'athletes:read','sessions:read','coins:write'
  rate_limit_per_min int DEFAULT 60,
  quota_per_day int DEFAULT 10000,
  used_today int DEFAULT 0,
  valid_until timestamptz,
  revoked_at timestamptz,
  last_used_at timestamptz,
  created_by uuid,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix) WHERE revoked_at IS NULL;
```

+ Endpoint `/api/v1/...` com middleware que aceita `Authorization: Bearer or_live_XXX` OU cookie session. Header scopes checked.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.3).