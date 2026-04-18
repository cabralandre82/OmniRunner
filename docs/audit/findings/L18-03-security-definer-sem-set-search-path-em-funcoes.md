---
id: L18-03
audit_ref: "18.3"
lens: 18
title: "SECURITY DEFINER sem SET search_path em funções antigas"
severity: critical
status: in-progress
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
tags: ["security", "hardening", "migration", "search-path"]
files:
  - supabase/migrations/20260417150000_search_path_hardening.sql
  - tools/integration_tests.ts
correction_type: migration
test_required: true
tests:
  - tools/integration_tests.ts
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
# [L18-03] SECURITY DEFINER sem SET search_path em funções antigas
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** in-progress
**Camada:** BACKEND (Supabase — todas funções `public.*` SECURITY DEFINER)
**Personas impactadas:** Toda a plataforma (indireto — defesa em profundidade)

## Achado
Funções `CREATE OR REPLACE ... SECURITY DEFINER` em migrations antigas
foram criadas sem `SET search_path`. Inventário ao vivo (supabase local):

- **30 SECURITY DEFINER em `public`**
- **26 sem `search_path`** (87%)
- **4 já hardenizadas** (via `20260303900000_security_definer_hardening_remaining.sql`, `20260322500000_medium_severity_fixes.sql`)

Funções afetadas (amostra):
```
custody_commit_coins, custody_release_committed, settle_clearing,
execute_swap, confirm_custody_deposit, increment_wallet_balance,
handle_new_user, handle_new_user_gamification,
fn_request_join, fn_approve_join_request, fn_reject_join_request,
fn_remove_member, fn_create_assessoria, fn_platform_approve_assessoria,
fn_platform_reject_assessoria, fn_platform_suspend_assessoria,
fn_search_coaching_groups, fn_lookup_group_by_invite_code,
fn_friends_activity_feed, compute_leaderboard_global_weekly,
cleanup_rate_limits, increment_rate_limit,
increment_profile_progress, staff_group_member_ids,
update_group_member_count
```

## Risco / Impacto
Search-path injection (defesa em profundidade):
SECURITY DEFINER sem `search_path` fixo herda o `search_path` da sessão do
chamador. Se um atacante:
1. Conseguir criar objetos em schema que precede `public` no resolver path,
2. E chamar a função DEFINER,
→ a função DEFINER executa lookups no schema malicioso primeiro. Exemplo:
```sql
CREATE FUNCTION attacker.coin_ledger(...) RETURNS ... AS $$
  -- código malicioso com privilégios do owner do SECURITY DEFINER (postgres)
$$;
SET search_path = 'attacker, public';
-- qualquer chamada a SECDEF fn agora pode pegar attacker.coin_ledger em vez de public.coin_ledger
```

**Mitigação atual (verificada em ambiente):**
- `anon`, `authenticated`, `service_role`: **sem** CREATE em `public`.
- `anon`, `authenticated`, `service_role`: **sem** CREATE em database (não podem criar schemas).

Ou seja, o ataque **não é diretamente explorável hoje**, mas:
- Qualquer regressão em permissões (GRANT acidental, migration elevando
  privilégios, role novo mal configurado) reabre o vetor.
- `postgres`, `supabase_auth_admin`, `supabase_storage_admin` têm permissões
  amplas — se alguma dessas roles for comprometida (ex: via bug em função
  DEFINER chamada por essas roles), a cadeia se completa.
- Custo de adicionar `SET search_path` é **zero em runtime** e fecha a
  classe inteira permanentemente.

## Correção implementada

**Nova migration:** `supabase/migrations/20260417150000_search_path_hardening.sql`

### 1. Batch hardening idempotente
```sql
DO $$ DECLARE r RECORD; BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args,
           coalesce(p.proconfig, ARRAY[]::text[]) AS cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef = true
    ORDER BY p.proname
  LOOP
    IF EXISTS (SELECT 1 FROM unnest(r.cfg) c WHERE c LIKE 'search_path=%') THEN
      CONTINUE;
    END IF;
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public, pg_temp',
                   r.proname, r.args);
    RAISE NOTICE '[L18-03] ALTER FUNCTION public.%(%) SET search_path = public, pg_temp',
                 r.proname, r.args;
  END LOOP;
END $$;
```

### 2. REVOKE CREATE ON SCHEMA public FROM PUBLIC
Idempotente (default em PG 15+). Garantido explicitamente.

### 3. Invariante de saída — migration FALHA se sobrar unhardened
```sql
DO $$ DECLARE v_remaining int; v_list text; BEGIN
  SELECT count(*), string_agg(...) INTO v_remaining, v_list
  FROM pg_proc ... WHERE prosecdef AND NOT ...search_path;
  IF v_remaining > 0 THEN
    RAISE EXCEPTION '[L18-03] % SECDEF still unhardened: %', v_remaining, v_list;
  END IF;
END $$;
```

### 4. View `security_definer_hardening_audit` (monitoring contínuo)
```sql
CREATE VIEW public.security_definer_hardening_audit AS
SELECT n.nspname AS schema, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS args,
       EXISTS(... search_path ...) AS has_search_path,
       p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef = true;
```

### 5. Testes de integração (2 novos em `tools/integration_tests.ts`)
- ✅ **Regressão blocker**: `WHERE has_search_path = false` deve retornar **zero** linhas.
  Falha lista exatamente quais funções ficaram de fora → devs sabem onde corrigir.
- ✅ View lista todas as SECDEF (sanity check de que a query está funcionando).

### Verificação executada (dry-run em supabase local)
```
[L18-03] Hardened 26 functions (4 already had search_path).
unhardened_after: 0
```

### Propriedades garantidas
- **Zero SECURITY DEFINER em `public` sem `search_path`** — verificado na própria
  migration (DO block com RAISE EXCEPTION em P0001).
- **Proteção contra regressão**: integration test bloqueia qualquer PR
  que crie uma nova SECDEF sem `search_path`.
- **Visibilidade**: view `security_definer_hardening_audit` disponível para
  dashboards e ad-hoc queries.
- **Idempotente**: migração pode rodar múltiplas vezes sem efeito colateral
  (o loop `CONTINUE`a quando já configurado).
- **Nenhuma quebra de API**: `ALTER FUNCTION` não altera assinatura nem
  comportamento, apenas o search_path interno.

### O que ainda falta
- [ ] Template de code review: adicionar checklist "novas funções
  SECURITY DEFINER têm `SET search_path = public, pg_temp`?". Tracking
  em L18-xx (DX / pr template).
- [ ] Regras para funções em schemas adicionais (`auth`, `storage`) se
  aplicável. Hoje escopo é `public` onde estão todas as funções da
  aplicação.

## Referência narrativa
Contexto completo e motivação detalhada em
[`docs/audit/parts/08-principal-eng.md`](../parts/08-principal-eng.md) —
anchor `[18.3]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.3).
- `2026-04-17` — Correção implementada: 26 SECDEF hardenizadas em batch,
  view de auditoria contínua + 2 testes de regressão bloqueando
  reintrodução do problema.
