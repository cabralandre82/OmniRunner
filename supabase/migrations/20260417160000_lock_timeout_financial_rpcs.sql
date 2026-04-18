-- ──────────────────────────────────────────────────────────────────────────
-- L19-05 — Correção: falta FOR UPDATE NOWAIT em funções de lock crítico
--
-- Referência auditoria:
--   docs/audit/findings/L19-05-falta-for-update-nowait-em-funcoes-de-lock.md
--   docs/audit/parts/07-vp-principal-dba-sre.md [19.5]
--
-- Problema:
--   RPCs financeiras (execute_burn_atomic, execute_swap, settle_clearing,
--   confirm_custody_deposit, emit_coins_atomic) fazem `SELECT ... FOR UPDATE`
--   sem limite de tempo para aquisição do lock. Se outra transação mantém
--   o lock por muito tempo (bug de long-running txn, connection stuck,
--   deadlock detection lag), a requisição fica pendurada até:
--     - statement_timeout da sessão (padrão: disabled em Supabase).
--     - TCP keepalive timeout do PGBouncer (costuma ser 60s+).
--     - Cliente/edge function timeout (10-30s).
--   Resultado: fila de requests se acumula, CPU do DB spikes, outras
--   transações começam a timeout em cascata.
--
--   Recomendação original do auditor: usar `FOR UPDATE NOWAIT` que falha
--   imediatamente com SQLSTATE 55P03 (lock_not_available) se o lock não
--   estiver disponível.
--
-- Correção escolhida: SET lock_timeout = '2s' por função via ALTER FUNCTION.
--
--   Vantagens vs reescrever FOR UPDATE NOWAIT:
--     - Não requer reescrever corpo das funções (safer, menos diff).
--     - Cobre TODAS as aquisições de lock (LWLock, row locks, triggers
--       internos) — não só os FOR UPDATE explícitos.
--     - Future-proof: novos FOR UPDATE adicionados ao corpo herdam o
--       timeout automaticamente.
--     - Semântica levemente diferente do NOWAIT puro: espera até 2s
--       antes de falhar, permitindo que contenção breve normal se
--       resolva sem erro. SQLSTATE final é o mesmo (55P03).
--
--   2s foi escolhido como safe default:
--     - Operações normais nessas RPCs completam em <100ms.
--     - Queue de 2s é aceitável para o cliente aguardar.
--     - Previne pileup: máximo ~30 requests/s em espera por função,
--       não milhares.
--
--   Cliente HTTP deve traduzir 55P03 em HTTP 503 + Retry-After: 2 para
--   que caller faça backoff exponencial. Implementado em
--   portal/src/app/api/distribute-coins/route.ts (cross-ref L02-01).
-- ──────────────────────────────────────────────────────────────────────────

-- 1. Lista canônica de RPCs financeiras críticas
-- Qualquer função que:
--   (a) acessa custody_accounts, wallets, clearing_settlements, clearing_events
--   (b) modifica valores monetários
--   (c) é chamada por portal/edge em request hot path
-- DEVE ter lock_timeout configurado.

DO $$
DECLARE
  r               RECORD;
  v_target_list   text[] := ARRAY[
    'execute_burn_atomic',
    'execute_swap',
    'settle_clearing',
    'confirm_custody_deposit',
    'emit_coins_atomic',
    'custody_commit_coins',
    'custody_release_committed',
    'increment_wallet_balance',
    'decrement_token_inventory'
  ];
  v_applied       integer := 0;
  v_not_found     text[] := ARRAY[]::text[];
  v_name          text;
BEGIN
  -- Identifica ausências (função prevista mas não deployada)
  FOREACH v_name IN ARRAY v_target_list LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_name
    ) THEN
      v_not_found := array_append(v_not_found, v_name);
    END IF;
  END LOOP;

  IF array_length(v_not_found, 1) > 0 THEN
    RAISE NOTICE '[L19-05] Funções não deployadas (ignoradas): %', v_not_found;
  END IF;

  -- Aplica lock_timeout em todas as instâncias (overload-safe via loop em pg_proc)
  FOR r IN
    SELECT
      p.proname,
      pg_get_function_identity_arguments(p.oid) AS args,
      coalesce(p.proconfig, ARRAY[]::text[])    AS cfg
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(v_target_list)
  LOOP
    IF EXISTS (SELECT 1 FROM unnest(r.cfg) c WHERE c LIKE 'lock_timeout=%') THEN
      RAISE NOTICE '[L19-05] public.%(%) já tem lock_timeout — skip',
        r.proname, r.args;
      CONTINUE;
    END IF;

    EXECUTE format(
      'ALTER FUNCTION public.%I(%s) SET lock_timeout = ''2s''',
      r.proname, r.args
    );
    v_applied := v_applied + 1;
    RAISE NOTICE '[L19-05] ALTER FUNCTION public.%(%) SET lock_timeout = 2s',
      r.proname, r.args;
  END LOOP;

  RAISE NOTICE '[L19-05] Applied lock_timeout to % function overloads', v_applied;
END $$;


-- 2. View de auditoria — status de lock_timeout nas funções financeiras
CREATE OR REPLACE VIEW public.financial_rpc_lock_config_audit AS
WITH target_fns AS (
  SELECT unnest(ARRAY[
    'execute_burn_atomic',
    'execute_swap',
    'settle_clearing',
    'confirm_custody_deposit',
    'emit_coins_atomic',
    'custody_commit_coins',
    'custody_release_committed',
    'increment_wallet_balance',
    'decrement_token_inventory'
  ])::text AS proname
)
SELECT
  t.proname                                                          AS function_name,
  (SELECT pg_get_function_identity_arguments(p.oid)
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = t.proname
   LIMIT 1)                                                          AS args,
  EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = t.proname
  )                                                                  AS deployed,
  (
    SELECT (
      SELECT c FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) c
      WHERE c LIKE 'lock_timeout=%' LIMIT 1
    )
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = t.proname
    LIMIT 1
  )                                                                  AS lock_timeout_setting,
  (
    SELECT EXISTS (
      SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) c
      WHERE c LIKE 'lock_timeout=%'
    )
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = t.proname
    LIMIT 1
  )                                                                  AS has_lock_timeout
FROM target_fns t;

COMMENT ON VIEW public.financial_rpc_lock_config_audit IS
  'L19-05: auditoria contínua de lock_timeout nas RPCs financeiras críticas. '
  'Toda função em target_fns DEVE ter has_lock_timeout=true OU deployed=false. '
  'Integration test bloqueia PRs que reintroduzam regressão.';

GRANT SELECT ON public.financial_rpc_lock_config_audit TO service_role;


-- 3. Invariante final — se alguma função deployada ficou sem lock_timeout, falha
DO $$
DECLARE
  v_missing integer;
  v_list    text;
BEGIN
  SELECT count(*),
         string_agg(function_name, ', ')
    INTO v_missing, v_list
  FROM public.financial_rpc_lock_config_audit
  WHERE deployed = true AND has_lock_timeout = false;

  IF v_missing > 0 THEN
    RAISE EXCEPTION '[L19-05] % financial RPC(s) deployed without lock_timeout: %',
      v_missing, v_list
      USING ERRCODE = 'P0001';
  END IF;
END $$;
