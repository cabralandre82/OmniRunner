-- ============================================================================
-- L19-08 — Standardize CHECK constraint naming on financial tables
-- ============================================================================
--
-- Finding (docs/audit/findings/L19-08-*.md):
--   "Algumas tabelas têm chk_peg_1_to_1, outras usam nome auto-gerado
--    custody_accounts_total_deposited_usd_check. Em erros, frontend mostra
--    nome feio."
--
-- Design decision (2026-04-21):
--   Um rename em massa das auto-geradas quebra ~25 migrations que fazem
--   `DROP CONSTRAINT IF EXISTS <table>_<col>_check` (ex.: 20260303100000,
--    20260227400000, 20260316000000, etc.). Seria possível bater replay +
--    ajustar todas, mas o custo/risco é alto vs o ganho real (o nome
--    auto-gerado É informativo — table_col_check diz a que column ele
--    se refere).
--
--   Adotamos convenção forward-only de **DUAS** formas aceitas:
--     (A) `<table>_<col>_check`  — postgres default, aceito.
--     (B) `chk_<table>_<rule>`   — ad-hoc, nomeado explicitamente.
--
--   Qualquer nome que NÃO se encaixe em (A) ou (B) é rejeitado pela
--   nova função `fn_find_nonstandard_check_constraints`.
--
--   Os renames IMEDIATOS que fazemos aqui são constraints ad-hoc sem o
--   prefixo `chk_` (detectadas em grep + inspeção e pelo CI
--   `audit:constraint-naming`):
--     - clearing_settlements.different_groups           → chk_clearing_settlements_distinct_groups
--     - swap_orders.swap_different_groups               → chk_swap_orders_distinct_groups
--     - coin_ledger.coin_ledger_reason_length_guard     → chk_coin_ledger_reason_length_guard
--     - coin_ledger.coin_ledger_reason_pii_guard        → chk_coin_ledger_reason_pii_guard
--   Todos são privately-referenced (só a migration que criou define;
--   comentários/testes são strings soltas que atualizamos aqui também).
--
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. RENAME das 2 constraints ad-hoc reais
-- ──────────────────────────────────────────────────────────────────────────

-- clearing_settlements.different_groups → chk_clearing_settlements_distinct_groups
DO $rename_cs$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='clearing_settlements'
      AND con.conname='different_groups'
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='clearing_settlements'
      AND con.conname='chk_clearing_settlements_distinct_groups'
  ) THEN
    ALTER TABLE public.clearing_settlements
      RENAME CONSTRAINT different_groups TO chk_clearing_settlements_distinct_groups;
  END IF;
END $rename_cs$;

-- coin_ledger.coin_ledger_reason_length_guard → chk_coin_ledger_reason_length_guard
DO $rename_cll$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='coin_ledger'
      AND con.conname='coin_ledger_reason_length_guard'
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='coin_ledger'
      AND con.conname='chk_coin_ledger_reason_length_guard'
  ) THEN
    ALTER TABLE public.coin_ledger
      RENAME CONSTRAINT coin_ledger_reason_length_guard TO chk_coin_ledger_reason_length_guard;
  END IF;
END $rename_cll$;

-- coin_ledger.coin_ledger_reason_pii_guard → chk_coin_ledger_reason_pii_guard
DO $rename_clp$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='coin_ledger'
      AND con.conname='coin_ledger_reason_pii_guard'
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='coin_ledger'
      AND con.conname='chk_coin_ledger_reason_pii_guard'
  ) THEN
    ALTER TABLE public.coin_ledger
      RENAME CONSTRAINT coin_ledger_reason_pii_guard TO chk_coin_ledger_reason_pii_guard;
  END IF;
END $rename_clp$;

-- swap_orders.swap_different_groups → chk_swap_orders_distinct_groups
DO $rename_so$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='swap_orders'
      AND con.conname='swap_different_groups'
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='swap_orders'
      AND con.conname='chk_swap_orders_distinct_groups'
  ) THEN
    ALTER TABLE public.swap_orders
      RENAME CONSTRAINT swap_different_groups TO chk_swap_orders_distinct_groups;
  END IF;
END $rename_so$;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. public.fn_find_nonstandard_check_constraints
-- ──────────────────────────────────────────────────────────────────────────
-- Retorna CHECK constraints cujo nome NÃO se encaixa em nenhum dos dois
-- padrões aceitos. Auto-generated pelo PG no formato `<table>_<col>_check`
-- ou `<table>_<col1>_<col2>_check` é OK. Nome ad-hoc com prefixo `chk_` é OK.
-- Todos os outros (como o histórico `different_groups`) são flaggados.
--
-- Excluded scope:
--   - FK / PK / UNIQUE constraints — outras lentes (L19-08 é só CHECK).
--   - CHECK em DOMAIN / composite types — fora.
--   - CHECK em partitions atached (inherited) — retornamos a partir da
--     partition root para evitar duplicar com a inheritance chain.

CREATE OR REPLACE FUNCTION public.fn_find_nonstandard_check_constraints(
  p_schema text DEFAULT 'public',
  p_table  text DEFAULT NULL
)
RETURNS TABLE (
  schemaname       text,
  tablename        text,
  constraint_name  text,
  suggested_name   text,
  definition       text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
  SELECT
    n.nspname::text  AS schemaname,
    c.relname::text  AS tablename,
    con.conname::text AS constraint_name,
    -- Sugestão: começar com chk_<table>_ e deixar o DBA preencher o <rule>
    format('chk_%s_%s', c.relname, regexp_replace(con.conname, '[^a-z0-9]+', '_', 'gi'))::text
      AS suggested_name,
    pg_get_constraintdef(con.oid)::text AS definition
  FROM pg_constraint con
  JOIN pg_class c ON c.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE con.contype = 'c'
    AND n.nspname = p_schema
    AND (p_table IS NULL OR c.relname = p_table)
    AND c.relkind IN ('r','p')
    AND NOT con.conislocal IS FALSE  -- só locais à tabela (não inherited)
    -- Padrão A: <table>_<anything>_check
    AND con.conname !~ ('^' || c.relname || '_[a-z0-9_]+_check$')
    -- Padrão B: chk_<table>_<anything>
    AND con.conname !~ '^chk_[a-z0-9_]+$'
  ORDER BY c.relname, con.conname;
$fn$;

COMMENT ON FUNCTION public.fn_find_nonstandard_check_constraints(text, text) IS
  'L19-08: lista CHECK constraints cujo nome não é (A) <table>_<col>_check '
  'auto-gerado pelo Postgres nem (B) chk_<table>_<rule> convenção ad-hoc. '
  'Retorna (schemaname, tablename, constraint_name, suggested_name, definition). '
  'See DB_CHECK_CONSTRAINT_NAMING_RUNBOOK.md.';

REVOKE ALL ON FUNCTION public.fn_find_nonstandard_check_constraints(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_find_nonstandard_check_constraints(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_find_nonstandard_check_constraints(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_find_nonstandard_check_constraints(text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. public.fn_assert_check_constraints_standardized
-- ──────────────────────────────────────────────────────────────────────────
-- Raise P0010 com lista estruturada quando find_nonstandard retornar > 0.

CREATE OR REPLACE FUNCTION public.fn_assert_check_constraints_standardized(
  p_schemas text[] DEFAULT ARRAY['public']::text[],
  p_tables  text[] DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_row  record;
  v_list text := '';
  v_cnt  integer := 0;
BEGIN
  IF p_schemas IS NULL OR array_length(p_schemas, 1) IS NULL THEN
    RAISE EXCEPTION 'p_schemas must be non-empty' USING ERRCODE = '22023';
  END IF;

  FOR v_row IN
    SELECT d.*
      FROM unnest(p_schemas) AS s(schemaname)
      CROSS JOIN LATERAL (
        SELECT *
          FROM public.fn_find_nonstandard_check_constraints(s.schemaname, NULL)
         WHERE (p_tables IS NULL) OR (tablename = ANY (p_tables))
      ) d
  LOOP
    v_cnt := v_cnt + 1;
    v_list := v_list || format(
      E'\n  - %I.%I.%I → sugerido %I (%s)',
      v_row.schemaname, v_row.tablename, v_row.constraint_name,
      v_row.suggested_name, v_row.definition
    );
  END LOOP;

  IF v_cnt > 0 THEN
    RAISE EXCEPTION 'L19-08: %s CHECK constraints com nome fora da convenção: %',
      v_cnt::text, v_list
      USING ERRCODE = 'P0010',
            HINT = 'Aceitos: <table>_<col>_check (pg default) OU chk_<table>_<rule>. '
                   'Rename via ALTER TABLE ... RENAME CONSTRAINT. '
                   'See docs/runbooks/DB_CHECK_CONSTRAINT_NAMING_RUNBOOK.md.';
  END IF;

  RETURN true;
END;
$fn$;

COMMENT ON FUNCTION public.fn_assert_check_constraints_standardized(text[], text[]) IS
  'L19-08: raise P0010 se fn_find_nonstandard_check_constraints retornar qualquer '
  'linha no escopo. Usado em CI (npm run audit:constraint-naming) e em self-tests.';

REVOKE ALL ON FUNCTION public.fn_assert_check_constraints_standardized(text[], text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_assert_check_constraints_standardized(text[], text[]) FROM anon;
REVOKE ALL ON FUNCTION public.fn_assert_check_constraints_standardized(text[], text[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_assert_check_constraints_standardized(text[], text[]) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Self-test DO block
-- ──────────────────────────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_count          integer;
  v_nonstandard    integer;
BEGIN
  -- (a) 2 funções registradas SECURITY DEFINER
  SELECT count(*)::int INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN (
       'fn_find_nonstandard_check_constraints',
       'fn_assert_check_constraints_standardized'
     )
     AND p.prosecdef = true;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'L19-08 selftest: expected 2 SECURITY DEFINER functions, got %', v_count;
  END IF;

  -- (b) As 4 constraints ad-hoc foram renomeadas
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'different_groups' AND contype = 'c'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: clearing_settlements.different_groups ainda existe';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'swap_different_groups' AND contype = 'c'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: swap_orders.swap_different_groups ainda existe';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'coin_ledger_reason_length_guard' AND contype = 'c'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: coin_ledger.coin_ledger_reason_length_guard ainda existe';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'coin_ledger_reason_pii_guard' AND contype = 'c'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: coin_ledger.coin_ledger_reason_pii_guard ainda existe';
  END IF;

  -- (c) As novas names existem (idempotência válida em re-apply)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    WHERE c.relname = 'clearing_settlements'
      AND con.conname = 'chk_clearing_settlements_distinct_groups'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: chk_clearing_settlements_distinct_groups not found';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    WHERE c.relname = 'swap_orders'
      AND con.conname = 'chk_swap_orders_distinct_groups'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: chk_swap_orders_distinct_groups not found';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    WHERE c.relname = 'coin_ledger'
      AND con.conname = 'chk_coin_ledger_reason_length_guard'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: chk_coin_ledger_reason_length_guard not found';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    WHERE c.relname = 'coin_ledger'
      AND con.conname = 'chk_coin_ledger_reason_pii_guard'
  ) THEN
    RAISE EXCEPTION 'L19-08 selftest: chk_coin_ledger_reason_pii_guard not found';
  END IF;

  -- (d) Nas 2 tabelas específicas, fn_find_nonstandard retorna 0 agora
  SELECT count(*)::int INTO v_nonstandard
    FROM public.fn_find_nonstandard_check_constraints('public', 'clearing_settlements');
  IF v_nonstandard <> 0 THEN
    RAISE EXCEPTION 'L19-08 selftest: clearing_settlements tem % non-standard constraints', v_nonstandard;
  END IF;

  SELECT count(*)::int INTO v_nonstandard
    FROM public.fn_find_nonstandard_check_constraints('public', 'swap_orders');
  IF v_nonstandard <> 0 THEN
    RAISE EXCEPTION 'L19-08 selftest: swap_orders tem % non-standard constraints', v_nonstandard;
  END IF;

  -- (e) Fabricar constraint não-conforme em schema temp + verificar detecção
  CREATE SCHEMA IF NOT EXISTS l19_08_test;
  CREATE TABLE IF NOT EXISTS l19_08_test.t (
    x int CONSTRAINT badly_named CHECK (x > 0)
  );

  SELECT count(*)::int INTO v_nonstandard
    FROM public.fn_find_nonstandard_check_constraints('l19_08_test', 't');
  IF v_nonstandard <> 1 THEN
    RAISE EXCEPTION 'L19-08 selftest: expected 1 nonstandard in l19_08_test.t, got %', v_nonstandard;
  END IF;

  -- (f) Assert wrapper raises P0010
  BEGIN
    PERFORM public.fn_assert_check_constraints_standardized(
      p_schemas => ARRAY['l19_08_test']::text[],
      p_tables  => ARRAY['t']::text[]
    );
    RAISE EXCEPTION 'L19-08 selftest: expected P0010 on non-conforming constraint';
  EXCEPTION
    WHEN sqlstate 'P0010' THEN
      NULL; -- expected
  END;

  DROP SCHEMA l19_08_test CASCADE;

  RAISE NOTICE '[L19-08.selftest] OK — 6 phases pass';
END $selftest$;

COMMIT;
