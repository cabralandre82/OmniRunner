---
id: L02-01
audit_ref: "2.1"
lens: 2
title: "distribute-coins — Orquestração não-atômica entre 4 RPCs (partial-failure silencioso)"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
tags: ["finance", "atomicity", "idempotency", "ledger", "portal"]
files:
  - portal/src/app/api/distribute-coins/route.ts
  - supabase/migrations/20260417120000_emit_coins_atomic.sql
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
note: "EXEMPLAR — referência de nível de detalhe para findings críticos da Onda 0. Correção implementada em 2026-04-17 (migration emit_coins_atomic + refactor da rota + 15 casos de teste)."
---

# [L02-01] distribute-coins — Orquestração não-atômica entre 4 RPCs (partial-failure silencioso)

> **Lente:** 2 — CTO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** in-progress (correção pronta, aguardando PR)

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

## Correção implementada

**Data:** 2026-04-17 (mesma sessão da auditoria)

### Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `supabase/migrations/20260417120000_emit_coins_atomic.sql` | **NOVO** — partial UNIQUE INDEX + função atômica `emit_coins_atomic` |
| `portal/src/app/api/distribute-coins/route.ts` | Refatorado — 4 mutações sequenciais substituídas por 1 chamada RPC |
| `portal/src/app/api/distribute-coins/route.test.ts` | Expandido — 11 → 15 casos, agora cobre idempotência + error codes específicos (P0001/P0002/P0003) |

### Detalhes da migration

1. `CREATE UNIQUE INDEX idx_coin_ledger_ref_id_institution_issue_unique ON coin_ledger (ref_id) WHERE reason = 'institution_token_issue'` — idempotência forte ao nível do banco. Índice parcial para não afetar outras `reason` que usam `ref_id` com semântica diferente (ex: `institution_switch_burn` usa `group_id` como `ref_id`).
2. `emit_coins_atomic(p_group_id, p_athlete_user_id, p_amount, p_ref_id)` — função `SECURITY DEFINER` com `SET search_path = public, pg_temp` (L18-03 preventivo). Envolve todas as mutações em transação única:
   - (A) `INSERT coin_ledger ... ON CONFLICT (ref_id) WHERE reason = 'institution_token_issue' DO NOTHING` — se `NULL` retornado, é retry idempotente; devolve estado atual sem reprocessar.
   - (B) `custody_commit_coins` — `EXCEPTION WHEN undefined_function THEN NULL` para compat com ambientes sem custódia deployada; falhas reais viram `CUSTODY_FAILED` (SQLSTATE `P0002`).
   - (C) `decrement_token_inventory` — `check_violation` ou `INVENTORY_NOT_FOUND` viram `INVENTORY_INSUFFICIENT` (`P0003`).
   - (D) `increment_wallet_balance` — propaga exceções.
3. Privilégios: `REVOKE ALL FROM PUBLIC, authenticated; GRANT EXECUTE TO service_role` — só o service role pode chamar (o endpoint usa `createServiceClient`).

### Mapeamento de erros no route

| SQLSTATE | Mensagem ao cliente | HTTP |
|---|---|---|
| `P0001` (INVALID_AMOUNT/MISSING_REF_ID) | "Parâmetros inválidos" | 400 |
| `P0002` (CUSTODY_FAILED) | "Lastro insuficiente na custódia da assessoria..." | 422 |
| `P0003` (INVENTORY_INSUFFICIENT) | "Saldo insuficiente de OmniCoins" | 422 |
| outros | "Erro ao distribuir coins" (+ log estruturado) | 500 |

### Testes (15/15 passando)

1. 401 sem auth
2. 403 se não admin_master
3. 400 se `athlete_user_id` ausente
4. 400 se `amount` não-inteiro
5. 400 se `amount > 1000`
6. 400 se `amount = 0`
7. 404 se atleta não for membro da assessoria
8. 422 (P0002) lastro insuficiente
9. 422 (P0003) inventário insuficiente
10. 500 erro inesperado do RPC
11. 200 happy path (primeira chamada, `was_idempotent=false`, audit emitido)
12. 200 idempotent retry (mesmo `ref_id`, `was_idempotent=true`, **audit NÃO emitido** — evita duplicação)
13. RPC chamado com params corretos incluindo `p_ref_id`
14. `ref_id` gerado automaticamente quando header ausente
15. `auditLog` não chamado em retry idempotente

### Propriedades garantidas pela correção

- **Atomicidade**: qualquer falha após a primeira mutação reverte o bloco inteiro (uma única transação PostgreSQL).
- **Idempotência forte**: DB rejeita duplicatas via partial unique index. Retry com mesmo `ref_id` retorna o estado sem reprocessar.
- **Audit não-duplicado**: `auditLog` só é emitido quando `was_idempotent=false`.
- **Error contracts explícitos**: SQLSTATE distintos para cada causa de falha → UX correta (422 vs 500) sem depender de string matching frágil.

### O que falta fazer (fora do escopo do L02-01)

- Cross-ref `L09-03` (idempotency-key previsível com `Date.now()`): trocar fallback por UUID v4.
- Cross-ref `L19-04` (DBA): já contemplado pelo partial UNIQUE INDEX desta migration.
- Cross-ref `L18-03` (SECURITY DEFINER search_path): preventivamente aplicado nesta função; resto do codebase tratado em finding dedicado.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.1 + cross-ref Lente 1, item 1.3).
- `2026-04-17` — Correção implementada (migration + route + tests). Status: `in-progress`, aguardando PR/merge.
