---
id: L01-03
audit_ref: "1.3"
lens: 1
title: "POST /api/distribute-coins — Distribuição de coins a atleta"
severity: critical
status: fixed
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "atomicity", "mobile", "portal", "migration", "testing"]
files:
  - portal/src/app/api/distribute-coins/route.ts
  - portal/src/app/api/distribute-coins/route.test.ts
  - supabase/migrations/20260417120000_emit_coins_atomic.sql
correction_type: code
test_required: true
tests:
  - portal/src/app/api/distribute-coins/route.test.ts
linked_issues: []
linked_prs:
  - "commit:affc69b"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: L02-01
deferred_to_wave: null
note: "Corrigido junto com L02-01 (mesma rota, mesmas mudanças). Ver detalhes em docs/audit/findings/L02-01-*.md. O fallback silencioso de custody_commit_coins é tratado via SQLSTATE P0002 (propagado como 422 'Lastro insuficiente' — não mais silencioso)."
---
# [L01-03] POST /api/distribute-coins — Distribuição de coins a atleta
> **Lente:** 1 — CISO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟢 fixed · **Duplicate of:** [L02-01](./L02-01-distribute-coins-orquestracao-nao-atomica-entre-4-rpcs.md)
**Camada:** PORTAL
**Personas impactadas:** Atleta, Assessoria, Plataforma
## Achado
`portal/src/app/api/distribute-coins/route.ts:97-110` tem um **fallback silencioso**: se a RPC `custody_commit_coins` não existir (`could not find`), o código *prossegue com a distribuição sem commit de lastro*. O comentário "custody_commit_coins RPC may not exist yet" prova que isto é intencional para compatibilidade histórica, mas hoje em produção a RPC existe (migration 20260228150001_custody_clearing_model.sql:232) — qualquer regressão de migration re-habilita emissão sem lastro.
  - Orquestração **não-atômica** entre 4 operações (custody_commit → decrement_token_inventory → increment_wallet_balance → coin_ledger insert). Se o processo Vercel for morto entre `decrement_token_inventory` (linha 113) e `increment_wallet_balance` (linha 129), **o grupo perde inventário e o atleta NÃO recebe as coins**; não há rollback.
  - `ledgerErr` (linha 151) é apenas logado; wallet balance já foi creditado mas audit trail está incompleto.
## Risco / Impacto

(a) Inflação monetária sem lastro se commit silencioso ocorrer. (b) Perda de inventário operacional do grupo sem contrapartida ao atleta — gera suporte-tickets e possivelmente pagamentos de compensação manuais. (c) Auditoria financeira quebrada se `coin_ledger` falhar (CFO não consegue reconciliar).

## Correção proposta

1. Criar RPC SQL `distribute_coins_atomic(p_group_id uuid, p_athlete uuid, p_amount int, p_ref_id text)` com `SECURITY DEFINER` que executa **em uma única transação**: commit custody, decrement inventory, increment wallet, insert ledger, insert audit. `FOR UPDATE` em `coaching_token_inventory` e `custody_accounts`.
  2. Remover o fallback silencioso — falhar com 500 se `custody_commit_coins` não existir.
  ```sql
  CREATE OR REPLACE FUNCTION public.distribute_coins_atomic(...)
    RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
  BEGIN
    PERFORM 1 FROM custody_accounts WHERE group_id = p_group_id FOR UPDATE;
    PERFORM custody_commit_coins(p_group_id, p_amount);
    PERFORM decrement_token_inventory(p_group_id, p_amount);
    PERFORM increment_wallet_balance(p_athlete, p_amount);
    INSERT INTO coin_ledger (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
      VALUES (p_athlete, p_amount, 'institution_token_issue', p_ref_id, p_group_id, EXTRACT(EPOCH FROM now())::BIGINT * 1000);
    RETURN jsonb_build_object('status', 'ok');
  END; $$;
  ```

## Teste de regressão

`portal/src/app/api/distribute-coins/route.test.ts` — mock de `custody_commit_coins` retornando "could not find" → verificar response 500, nenhum ledger insertado. Também: teste de crash simulado entre RPCs.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.3).
- `2026-04-17` — Corrigido em conjunto com L02-01 (commit `affc69b`): rota refatorada para `emit_coins_atomic` RPC, fallback silencioso eliminado (P0002 → 422 explícito).
- `2026-04-17` — E2E green (`tools/validate-migrations.sh --run-tests` 165/165 + 146/146). Promovido a `fixed`.