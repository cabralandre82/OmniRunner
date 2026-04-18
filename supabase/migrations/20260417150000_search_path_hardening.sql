-- ──────────────────────────────────────────────────────────────────────────
-- L18-03 — Correção: SECURITY DEFINER sem SET search_path em funções antigas
--
-- Referência auditoria:
--   docs/audit/findings/L18-03-security-definer-sem-set-search-path-em-funcoes.md
--   docs/audit/parts/08-principal-eng.md [18.3]
--
-- Problema:
--   Funções `CREATE OR REPLACE ... SECURITY DEFINER` em migrations antigas
--   (20260228160001_burn_plan_atomic.sql, 20260228170000_custody_gaps.sql,
--   diversas em 20260228150001_custody_clearing_model.sql, etc) foram criadas
--   sem `SET search_path = public, pg_temp`. Funções SECURITY DEFINER sem
--   search_path fixo herdam o search_path da sessão do chamador — se um
--   atacante controla essa configuração E consegue criar objetos em schema
--   que precede `public`, a função DEFINER pode chamar objetos maliciosos.
--
--   Mitigação atual (defesa em profundidade já aplicada):
--     - anon, authenticated, service_role: sem CREATE em schema public.
--     - anon, authenticated, service_role: sem CREATE em database.
--     - Schemas customizados não podem ser criados por roles de aplicação.
--
--   Porém: qualquer regressão em permissões (GRANT acidental, migration
--   elevando privilégios) reabre o vetor. O custo de adicionar SET
--   search_path é zero em runtime e fecha a classe inteira.
--
-- Correção:
--   (1) Loop idempotente aplicando `ALTER FUNCTION ... SET search_path =
--       public, pg_temp` a TODAS as SECURITY DEFINER em `public` que ainda
--       não tenham search_path configurado.
--   (2) REVOKE CREATE ON SCHEMA public FROM PUBLIC (idempotente, default em
--       PG 15+ já é este, mas garantimos explicitamente).
--   (3) Invariante final: a migration FALHA se sobrar qualquer SECURITY
--       DEFINER em `public` sem search_path.
--
--   Migrations futuras que criarem novas SECURITY DEFINER DEVEM incluir
--   `SET search_path = public, pg_temp` inline no CREATE. O teste de
--   integração (tools/integration_tests.ts L18-03) falha o CI se violar.
-- ──────────────────────────────────────────────────────────────────────────

-- 1. Defesa base: sem CREATE em public para PUBLIC
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- 2. Hardening em batch
DO $$
DECLARE
  r            RECORD;
  v_altered    integer := 0;
  v_skipped    integer := 0;
  v_ident      text;
BEGIN
  FOR r IN
    SELECT
      p.oid,
      p.proname,
      pg_get_function_identity_arguments(p.oid) AS args,
      coalesce(p.proconfig, ARRAY[]::text[])    AS cfg
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
    ORDER BY p.proname
  LOOP
    IF EXISTS (
      SELECT 1 FROM unnest(r.cfg) c WHERE c LIKE 'search_path=%'
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    v_ident := format('public.%I(%s)', r.proname, r.args);
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path = public, pg_temp',
      v_ident
    );
    v_altered := v_altered + 1;
    RAISE NOTICE '[L18-03] ALTER FUNCTION % SET search_path = public, pg_temp', v_ident;
  END LOOP;

  RAISE NOTICE '[L18-03] Hardened % functions (% already had search_path).',
    v_altered, v_skipped;
END $$;

-- 3. Invariante final — FALHA a migration se restar SECDEF sem search_path
DO $$
DECLARE
  v_remaining integer;
  v_list      text;
BEGIN
  SELECT count(*),
         string_agg(format('public.%I(%s)', p.proname,
                           pg_get_function_identity_arguments(p.oid)), ', ')
    INTO v_remaining, v_list
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND NOT EXISTS (
      SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) c
      WHERE c LIKE 'search_path=%'
    );

  IF v_remaining > 0 THEN
    RAISE EXCEPTION '[L18-03] % SECURITY DEFINER function(s) still missing search_path: %',
      v_remaining, v_list
      USING ERRCODE = 'P0001';
  END IF;
END $$;

-- 4. Marker view para monitoring contínuo (integration test + dashboard)
-- Se esta view retornar linhas, significa que uma migration posterior criou
-- uma nova SECURITY DEFINER sem search_path. L18-03 regression.
CREATE OR REPLACE VIEW public.security_definer_hardening_audit AS
SELECT
  n.nspname                                      AS schema,
  p.proname                                      AS function_name,
  pg_get_function_identity_arguments(p.oid)      AS args,
  EXISTS (
    SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) c
    WHERE c LIKE 'search_path=%'
  )                                              AS has_search_path,
  coalesce(p.proconfig, ARRAY[]::text[])         AS proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true;

COMMENT ON VIEW public.security_definer_hardening_audit IS
  'L18-03: inventário de funções SECURITY DEFINER em public com status de '
  'search_path. Toda nova função DEFINER DEVE ter has_search_path=true. '
  'Integration test (tools/integration_tests.ts) bloqueia regressões.';

GRANT SELECT ON public.security_definer_hardening_audit TO service_role;
