---
id: L05-04
audit_ref: "5.4"
lens: 5
title: "Challenge/Championship: participante pode retirar-se (withdraw) durante disputa — sem regra de cutoff"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["edge-function", "migration", "performance", "reliability"]
files:
  - supabase/functions/challenge-withdraw/index.ts
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
# [L05-04] Challenge/Championship: participante pode retirar-se (withdraw) durante disputa — sem regra de cutoff
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/challenge-withdraw/index.ts` provavelmente permite withdraw a qualquer momento. Sem regra "não pode sair nas últimas 48 h de um challenge de 7 dias".
## Risco / Impacto

— Atleta próximo do último lugar desiste para não "estragar" a estatística → gamificação quebrada.

## Correção proposta

— Adicionar `ALTER TABLE challenges ADD COLUMN withdraw_cutoff_hours integer DEFAULT 48`. Edge Function verifica:

```typescript
if (challenge.ends_at - now() < cutoffHours * 3600e3)
  return jsonErr(422, "WITHDRAW_LOCKED", "Withdrawal closed 48h before end");
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.4).