---
id: L06-06
audit_ref: "6.6"
lens: 6
title: "Sem feature flags para desligar subsistemas"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "reliability"]
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
# [L06-06] Sem feature flags para desligar subsistemas
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Em caso de bug em swap/clearing/custody, a única forma de desligar é deploy. Não há tabela `feature_flags` consultada no início de cada Edge/Route Handler.
## Risco / Impacto

— Bug descoberto 02:00, deploy demora 20 min, perda estimada US$ X/min.

## Correção proposta

—

```sql
CREATE TABLE public.feature_flags (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT true,
  updated_by uuid,
  updated_at timestamptz DEFAULT now()
);
INSERT INTO feature_flags(key, enabled) VALUES
  ('swap.enabled', true),
  ('custody.deposits.enabled', true),
  ('custody.withdrawals.enabled', true),
  ('clearing.interclub.enabled', true),
  ('distribute_coins.enabled', true),
  ('auto_topup.enabled', true);
```

```typescript
export async function assertFeature(key: string) {
  const { data } = await db.from("feature_flags").select("enabled").eq("key", key).maybeSingle();
  if (!data?.enabled) throw new FeatureDisabledError(key);
}
```

Adicionar no começo de cada endpoint financeiro. UI `/platform/flags` para admin_master toggle imediato.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.6).