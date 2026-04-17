---
id: L16-05
audit_ref: "16.5"
lens: 16
title: "Integrações de marcas esportivas sem schema"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration"]
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