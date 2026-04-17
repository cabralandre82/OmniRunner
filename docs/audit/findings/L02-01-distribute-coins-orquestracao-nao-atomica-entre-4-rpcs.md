---
id: L02-01
audit_ref: "2.1"
lens: 2
title: "distribute-coins — Orquestração não-atômica entre 4 RPCs (partial-failure silencioso)"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "idempotency", "ledger", "portal"]
files:
  - portal/src/app/api/distribute-coins/route.ts
  - supabase/migrations/20260415020000_coin_ledger_group_visibility.sql
correction_type: code
test_required: true
tests:
  - portal/src/app/api/distribute-coins/route.test.ts
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "EXEMPLAR — referência de nível de detalhe para findings críticos da Onda 0"
---

# [L02-01] distribute-coins — Orquestração não-atômica entre 4 RPCs (partial-failure silencioso)

> **Lente:** 2 — CTO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending

**Camada:** PORTAL + BACKEND
**Personas impactadas:** Atleta, Assessoria, Plataforma (CFO)

## Contexto

O endpoint `POST /api/distribute-coins` do Portal emite OmniCoins de uma assessoria (admin_master) para um atleta. A operação envolve **3 mutações financeiras** executadas como **RPCs separados + INSERT direto**, sem uma única transação PostgreSQL englobando as três. Se a terceira falhar, as duas primeiras ficaram persistidas — o sistema registra no log e retorna 200 OK ao cliente.

## Evidência

A rota executa sequencialmente, em conexões potencialmente distintas do pool PostgREST:

```112:149:portal/src/app/api/distribute-coins/route.ts
  // Deduct from group inventory (atomic — CHECK >= 0 prevents overdraft)
  const { error: decrErr } = await db.rpc("decrement_token_inventory", {
    p_group_id: groupId,
    p_amount: amount,
  });
  // ... error handling returns 422/500 ...

  const { error: walletErr } = await db.rpc("increment_wallet_balance", {
    p_user_id: athlete_user_id,
    p_delta: amount,
  });
  // ... error handling returns 500 (mas inventory já foi debitado!) ...

  const refId = idempotencyKey ?? `portal_${user.id}_${Date.now()}`;
  const { error: ledgerErr } = await db.from("coin_ledger").insert({
    user_id: athlete_user_id,
    delta_coins: amount,
    reason: "institution_token_issue",
    ref_id: refId,
    issuer_group_id: groupId,
    created_at_ms: Date.now(),
  });
```

E o tratamento da falha do ledger apenas loga:

```151:158:portal/src/app/api/distribute-coins/route.ts
  if (ledgerErr) {
    logger.error("coin_ledger insert failed after successful distribution", ledgerErr, {
      athlete_user_id,
      amount,
      groupId,
      refId,
    });
  }
```

Cenários de falha parcial:

1. **Inventory debitado + Wallet NÃO creditada** — atleta perde coins, empresa pagou. Resposta: 500, sem rollback.
2. **Inventory debitado + Wallet creditada + Ledger NÃO inserido** — saldo "órfão" (não aparece em extratos, não reconciliável, idempotency-key quebra em retries). Resposta: **200 OK** — cliente não sabe que há corrupção.
3. **Race condition** — dois requests concorrentes com mesma `idempotency-key` podem passar pelo check de linha 56–71 antes de qualquer `INSERT` completar → **emissão dupla**.

## Risco / Impacto

- **Financeiro direto**: cada partial-failure é discrepância entre `custody_accounts.committed_coins`, `wallet_balances.balance` e `coin_ledger`. Reconciliação diária acusa drift sem imputar ao evento correto.
- **LGPD/Art. 19**: atleta pode judicializar diferença entre UI e realidade.
- **Suporte**: sem `ref_id` no ledger, não há como auditar "onde foram meus coins?" — custo ~2h dev sênior/ticket.
- **Confiança**: um único caso público destrói trust do produto em treinadores (principal persona pagante).

**Exposição**: baixo volume hoje (beta), mas escala linearmente. Com ~5k emissões/dia em GA, qualquer 4xx transitório de Supabase reproduz o cenário.

## Correção proposta

### Opção recomendada: RPC único `emit_coins_atomic`

Função SQL `SECURITY DEFINER` envolvendo as três mutações em transação única:

```sql
-- supabase/migrations/20260418000000_emit_coins_atomic.sql
CREATE OR REPLACE FUNCTION emit_coins_atomic(
  p_group_id uuid,
  p_athlete_user_id uuid,
  p_amount numeric,
  p_ref_id text,
  p_reason text DEFAULT 'institution_token_issue'
) RETURNS TABLE (ledger_id bigint, new_wallet_balance numeric)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_ledger_id bigint;
  v_new_balance numeric;
BEGIN
  INSERT INTO coin_ledger (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
  VALUES (p_athlete_user_id, p_amount, p_reason, p_ref_id, p_group_id, (extract(epoch from now()) * 1000)::bigint)
  ON CONFLICT (ref_id) DO NOTHING
  RETURNING id INTO v_ledger_id;

  IF v_ledger_id IS NULL THEN
    SELECT balance INTO v_new_balance FROM wallet_balances WHERE user_id = p_athlete_user_id;
    RETURN QUERY SELECT NULL::bigint, v_new_balance;
    RETURN;
  END IF;

  UPDATE token_inventory SET coins = coins - p_amount WHERE group_id = p_group_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVENTORY_MISSING' USING ERRCODE = 'P0002'; END IF;

  INSERT INTO wallet_balances (user_id, balance, updated_at)
  VALUES (p_athlete_user_id, p_amount, now())
  ON CONFLICT (user_id) DO UPDATE
    SET balance = wallet_balances.balance + EXCLUDED.balance, updated_at = now()
  RETURNING balance INTO v_new_balance;

  RETURN QUERY SELECT v_ledger_id, v_new_balance;
END;
$$;

REVOKE ALL ON FUNCTION emit_coins_atomic FROM PUBLIC;
GRANT EXECUTE ON FUNCTION emit_coins_atomic TO service_role;
```

E simplificação do `route.ts` para chamar o RPC único.

### Mudanças obrigatórias

1. Migration `supabase/migrations/20260418000000_emit_coins_atomic.sql` com função acima + `UNIQUE (ref_id)` em `coin_ledger`.
2. Refatoração de `portal/src/app/api/distribute-coins/route.ts`.
3. Migration de reconciliação para detectar registros órfãos pré-correção.

## Teste de regressão

Arquivo: `portal/src/app/api/distribute-coins/route.test.ts` (expandir).

Casos obrigatórios:

1. **Happy path** — 3 entradas consistentes.
2. **Idempotency replay** — mesmo `x-idempotency-key` duas vezes.
3. **Partial-failure simulada** — mockar falha em `INSERT coin_ledger` → `wallet_balances` e `token_inventory` permanecem inalterados.
4. **Concorrência** — 10 requests paralelos mesma idempotency-key → 1 sucede; 9 idempotentes.
5. **Inventory insuficiente** — saldo=10, emitir 100 → 422 sem mutação.

## Cross-refs

- `L01-03` (CISO): mesma rota com fallback silencioso quando `custody_commit_coins` "not found".
- `L03-02` (CFO): ausência de trilha de auditoria completa para `platform_revenue`.
- `L09-03` (CRO): idempotency-key com `Date.now()` previsível — atacante pode colidir.
- `L19-04` (DBA): índice em `coin_ledger.ref_id` precisa ser `UNIQUE` para `ON CONFLICT`.
- `L17-02` (VP Eng): teste existente cobre só happy path — cobertura de caminhos de falha = 0%.

## Referência narrativa

Contexto completo em `docs/audit/parts/02-cto-cfo.md` — anchor `[2.1]`.
Também auditado pela Lente 1 (CISO) como `[1.3]` em `docs/audit/parts/01-ciso.md`.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.1 + cross-ref Lente 1, item 1.3).
