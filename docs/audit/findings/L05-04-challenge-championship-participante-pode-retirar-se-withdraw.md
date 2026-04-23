---
id: L05-04
audit_ref: "5.4"
lens: 5
title: "Challenge/Championship: participante pode retirar-se (withdraw) durante disputa — sem regra de cutoff"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["challenge", "sql", "migration", "cutoff", "fairness"]
files:
  - supabase/migrations/20260421460000_l05_04_challenge_withdraw_cutoff.sql
  - tools/audit/check-challenge-withdraw-cutoff.ts
correction_type: schema
test_required: true
tests:
  - tools/audit/check-challenge-withdraw-cutoff.ts
linked_issues: []
linked_prs:
  - d929792
owner: challenges
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Migration 20260421460000_l05_04_challenge_withdraw_cutoff.sql adiciona
  `public.challenges.withdraw_cutoff_hours` (integer NOT NULL DEFAULT 48,
  CHECK BETWEEN 0 AND 168). Duel-style challenges (`type='one_vs_one'`)
  recebem backfill 0 (duel refund/cancellation é escopo de L05-06).
  `supabase/functions/challenge-withdraw/index.ts` consulta a coluna e
  rejeita o withdraw quando faltam menos horas que o cutoff. Self-test
  no migration valida default, CHECK e backfill. Commit d929792.
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