---
id: L16-05
audit_ref: "16.5"
lens: 16
title: "Integrações de marcas esportivas sem schema"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "migration"]
files:
  - supabase/migrations/20260421620000_l16_05_sponsorships.sql
  - tools/audit/check-sponsorships.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-sponsorships.ts
linked_issues: []
linked_prs:
  - "local:725159d"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in 725159d (J29). Extended `coin_ledger.reason` enum
  with `sponsorship_payout` so sponsor coin transfers are
  distinguishable from prize money and referrals in the
  ledger (preserves the existing audit trail). `public.brands`
  is the canonical brand catalogue — RLS allows public read
  of `is_active=true` brands so mobile can render logos.
  `public.sponsorships` captures contracts:
  `(group_id, brand_id)`, state machine (draft → active →
  expired/terminated), CHECKs enforcing
  `contract_end >= contract_start`,
  `monthly_coins_to_athletes >= 0`,
  `equipment_discount_pct BETWEEN 0 AND 100`; group staff
  manage via RLS. `public.sponsorship_athletes` is the
  LGPD-safe opt-in join (no automatic enrollment — athlete
  must consent). RPCs: `fn_sponsorship_activate` (admin-only,
  transitions draft → active), `fn_sponsorship_enroll_athlete`
  (athlete-self, idempotent), `fn_sponsorship_opt_out_athlete`
  (athlete-self), `fn_sponsorship_distribute_monthly_coins`
  (service-role cron target, idempotent per month via
  `ON CONFLICT`, honours `monthly_coins_to_athletes` budget).
  Invariants locked by `npm run audit:sponsorships`.
---
# [L16-05] Integrações de marcas esportivas sem schema
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Nike, Asics, Mizuno patrocinam atletas — produto não tem `sponsorships` table nem `team_equipment_recommendations`.
## Correção proposta

—

```sql
CREATE TABLE public.sponsorships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES coaching_groups(id),
  brand text NOT NULL,
  contract_start date,
  contract_end date,
  monthly_coins_to_athletes int DEFAULT 0,
  equipment_discount_pct numeric(4,1),
  partner_api_key_id uuid REFERENCES api_keys(id)
);
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.5).