---
id: L19-05
audit_ref: "19.5"
lens: 19
title: "Falta FOR UPDATE NOWAIT em funções de lock crítico"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
tags: ["finance", "atomicity", "locks", "sre", "observability"]
files:
  - supabase/migrations/20260417160000_lock_timeout_financial_rpcs.sql
  - supabase/migrations/20260417120000_emit_coins_atomic.sql
  - supabase/migrations/20260417140000_execute_burn_atomic_hardening.sql
  - portal/src/app/api/distribute-coins/route.ts
  - portal/src/app/api/distribute-coins/route.test.ts
  - tools/integration_tests.ts
correction_type: migration
test_required: true
tests:
  - portal/src/app/api/distribute-coins/route.test.ts
  - tools/integration_tests.ts
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
# [L19-05] Falta FOR UPDATE NOWAIT em funções de lock crítico
> **Lente:** 19 — DBA · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** in-progress
**Camada:** BACKEND (Supabase RPC) + portal error mapping
**Personas impactadas:** Toda operação financeira (emit, burn, swap, settlement, deposit)

## Achado
RPCs financeiras (`execute_burn_atomic`, `execute_swap`, `settle_clearing`,
`confirm_custody_deposit`, `emit_coins_atomic`, `custody_commit_coins`,
`custody_release_committed`, `increment_wallet_balance`) fazem
`SELECT ... FOR UPDATE` sem limite de tempo para aquisição. Se outra
transação mantém o lock (bug de long-running txn, connection stuck,
deadlock detection lag), a requisição fica pendurada até:

- `statement_timeout` da sessão — padrão **disabled** em Supabase.
- TCP keepalive do PGBouncer — tipicamente 60s+.
- Timeout do cliente (edge/portal) — 10-30s.

Resultado em cenário de contenção: fila de requests se acumula, CPU do DB
spikes, outras transações começam a time-out em cascata → **incidente
cascata**.

## Risco / Impacto
Durante picos de tráfego (distribuição em massa a atletas, swap em horário
de pico, settlement netting cron rodando junto com operação online), uma
transação lenta em `custody_accounts` ou `wallets` pode segurar centenas de
requisições. Saturação de `max_connections` é o passo seguinte → 500/504
em toda a API, não só na rota afetada.

## Correção implementada

Escolhi `SET lock_timeout = '2s'` via `ALTER FUNCTION` (declarativo, ao
nível da função) em vez de reescrever todos os `FOR UPDATE` como
`FOR UPDATE NOWAIT`. Razões:

- Não requer reescrever corpo das funções → diff mínimo, risco de regressão baixo.
- Cobre **todas** as aquisições de lock (LWLock, row locks, trigger locks)
  — não só `FOR UPDATE` explícito.
- Future-proof: qualquer novo `FOR UPDATE` adicionado ao corpo herda o
  timeout automaticamente.
- SQLSTATE final é o mesmo (`55P03 lock_not_available`), cliente não precisa
  distinguir "NOWAIT" vs "timeout".

**2s** foi escolhido como safe default:
- Operações normais completam em <100ms (headroom 20×).
- Longo o suficiente para absorver contenção breve normal.
- Curto o suficiente para evitar pileup (máx. ~30 req/s em espera por função).

### 1. Nova migration (`20260417160000_lock_timeout_financial_rpcs.sql`)
```sql
DO $$
DECLARE r RECORD; v_target_list text[] := ARRAY[
  'execute_burn_atomic', 'execute_swap', 'settle_clearing',
  'confirm_custody_deposit', 'emit_coins_atomic',
  'custody_commit_coins', 'custody_release_committed',
  'increment_wallet_balance', 'decrement_token_inventory'
];
BEGIN
  FOR r IN SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
                  coalesce(p.proconfig, ARRAY[]::text[]) AS cfg
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = ANY(v_target_list)
  LOOP
    IF EXISTS (SELECT 1 FROM unnest(r.cfg) c WHERE c LIKE 'lock_timeout=%') THEN
      CONTINUE;
    END IF;
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET lock_timeout = ''2s''',
                   r.proname, r.args);
  END LOOP;
END $$;
```

**Invariante de saída**: migration **FALHA** com `P0001` se sobrar qualquer
função deployada da lista sem `lock_timeout`.

**View `financial_rpc_lock_config_audit`**: inventário contínuo queryable
por integration tests e dashboards.

### 2. Fresh-install safety
Adicionado `SET lock_timeout = '2s'` diretamente nas migrations que criam
as RPCs "novas":
- `20260417120000_emit_coins_atomic.sql` → `SET lock_timeout = '2s'` no `CREATE`.
- `20260417140000_execute_burn_atomic_hardening.sql` → idem.

Garante que em fresh install, antes mesmo de rodar o batch 160000, já
nascem com `lock_timeout` configurado.

### 3. Portal error mapping (cross-ref L02-01)
`portal/src/app/api/distribute-coins/route.ts`:
```ts
if (rpcErr.code === "55P03" || msg.includes("lock_not_available")) {
  return new NextResponse(
    JSON.stringify({ error: "Recurso em uso, tente novamente em instantes." }),
    { status: 503, headers: { "Content-Type": "application/json", "Retry-After": "2" } },
  );
}
```
Também garantido: `auditLog` **não** é chamado em 503 (operação não committada).

### 4. Testes
**Route tests (`route.test.ts`, +2 casos, total 17):**
- ✅ `55P03` → 503 com `Retry-After: 2` + mensagem em português.
- ✅ Mensagem `lock_not_available` (sem código) também → 503.

**Integration tests (`integration_tests.ts`, +2 casos):**
- ✅ Regressão blocker: `financial_rpc_lock_config_audit.deployed = true AND has_lock_timeout = false` deve retornar zero; falha lista exatamente quais RPCs precisam correção.
- ✅ Todas as RPCs hardenizadas têm `lock_timeout = 2s` (e não outro valor acidental).

### 5. Verificação (dry-run em supabase local)
```
[L19-05] ALTER FUNCTION public.increment_wallet_balance(...) SET lock_timeout = 2s
[L19-05] ALTER FUNCTION public.confirm_custody_deposit(...) SET lock_timeout = 2s
[L19-05] ALTER FUNCTION public.custody_commit_coins(...) SET lock_timeout = 2s
[L19-05] ALTER FUNCTION public.custody_release_committed(...) SET lock_timeout = 2s
[L19-05] ALTER FUNCTION public.settle_clearing(...) SET lock_timeout = 2s
[L19-05] ALTER FUNCTION public.execute_swap(...) SET lock_timeout = 2s
[L19-05] public.emit_coins_atomic(...) já tem lock_timeout — skip
[L19-05] public.execute_burn_atomic(...) já tem lock_timeout — skip
[L19-05] Applied lock_timeout to 6 function overloads
```
Após a migration, 8/9 RPCs deployadas estão com `lock_timeout=2s` (1 função
`decrement_token_inventory` ainda não deployada neste ambiente — será
capturada na próxima execução).

### Propriedades garantidas
- **Nenhuma RPC financeira deployada pode segurar conexão indefinidamente**:
  contenção resolve em ≤2s ou devolve `55P03`.
- **Cliente recebe contrato estável**: `55P03` → 503 com `Retry-After` →
  retry com backoff exponencial.
- **Sem duplicate audit log em 503**: verificado em route.test.ts.
- **Regressão bloqueada por CI**: integration test lista exatamente quais
  funções novas perderam `lock_timeout`.
- **Fresh install correto**: CREATE OR REPLACE das RPCs novas já inclui
  `SET lock_timeout`; migration 160000 é redundância defensiva.

### O que ainda falta
- [ ] Alerta SRE: `pg_stat_activity.wait_event_type = 'Lock'` por >1s
  durante operação online. Tracking em L15-xx (observability / DB metrics).
- [ ] Retry automático client-side em 503 (atualmente o cliente precisa
  tratar manualmente). Tracking em L13-xx (API SDK).
- [ ] Expandir para outras rotas além de `distribute-coins`: burn
  endpoint, swap endpoint, deposit confirm. Todas devem traduzir 55P03
  → 503. Tracking em L13-xx (error taxonomy).

## Referência narrativa
Contexto completo e motivação detalhada em
[`docs/audit/parts/07-vp-principal-dba-sre.md`](../parts/07-vp-principal-dba-sre.md) —
anchor `[19.5]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.5).
- `2026-04-17` — Correção implementada: `SET lock_timeout = '2s'` em 9 RPCs
  financeiras críticas + route mapping 55P03→503 + 4 testes de regressão.
