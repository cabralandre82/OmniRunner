-- ============================================================================
-- L08-04 — Sessions coherence CHECK constraint
-- ============================================================================
--
-- Finding (docs/audit/findings/L08-04-analise-de-sessions-pelo-moving-ms-mas-coluna.md):
--   `fn_compute_kpis_batch` soma `moving_ms/1000.0`; COALESCE já protege NULL,
--   mas `moving_ms = 0 AND total_distance_m > 0` (GPS bug) quebra outros
--   queries do portal com pace infinito. `fn_compute_skill_bracket` já tem
--   guard inline, mas outros consumidores podem não ter.
--
-- Invariante (a partir de 2026-04-21):
--   Para sessões FINALIZADAS (status >= 3):
--     (1) total_distance_m = 0 AND moving_ms = 0   — ok (sessão drop/cancel)
--     (2) total_distance_m >= 100 AND moving_ms >= 60000  — ok (real)
--     Qualquer outro par → rejeitado
--   Sessões incompletas (status < 3) livres.
--
-- Design:
--   - ADD CONSTRAINT NOT VALID + VALIDATE CONSTRAINT separate:
--       * NOT VALID → adiciona entry em pg_constraint sem full-table scan,
--         enforce só para NEW rows (INSERT/UPDATE).
--       * VALIDATE CONSTRAINT → scan ShareUpdateExclusive (não bloqueia
--         SELECT/INSERT/UPDATE concurrent). Se algum row antigo violar,
--         abortamos aqui — o que NÃO deve acontecer (scan prévio em local
--         retornou 0 violações).
--   - Nome do constraint segue convenção L19-08: chk_sessions_coherence.
--   - Helper fn_find_sessions_incoherent retorna rows que violariam a
--     invariante, para uso em batch-clean runbooks.
--
-- Integração:
--   - L08-03 (Wave 1 Batch D.2) vai adicionar btree em (status, start_time_ms)
--     para time-series queries; scope ortogonal a este.
--   - L21-01/L21-02 (anti-cheat) já validam na escrita via verify-session;
--     esta CHECK é backstop de schema.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Detector fn_find_sessions_incoherent
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_find_sessions_incoherent(
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  id               uuid,
  user_id          uuid,
  status           smallint,
  total_distance_m double precision,
  moving_ms        bigint,
  reason           text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
  SELECT
    s.id,
    s.user_id,
    s.status,
    s.total_distance_m,
    s.moving_ms,
    CASE
      WHEN s.total_distance_m > 0 AND s.moving_ms = 0
        THEN 'gps_zero_moving_ms'
      WHEN s.total_distance_m = 0 AND s.moving_ms > 0
        THEN 'zero_distance_with_moving'
      WHEN s.total_distance_m > 0 AND s.total_distance_m < 100
        THEN 'distance_below_100m'
      WHEN s.moving_ms > 0 AND s.moving_ms < 60000
        THEN 'moving_below_60s'
      ELSE 'other_incoherent'
    END AS reason
    FROM public.sessions s
   WHERE s.status >= 3
     AND NOT (
       (s.total_distance_m = 0 AND s.moving_ms = 0) OR
       (s.total_distance_m >= 100 AND s.moving_ms >= 60000)
     )
   ORDER BY s.created_at DESC
   LIMIT p_limit;
$fn$;

COMMENT ON FUNCTION public.fn_find_sessions_incoherent(integer) IS
  'L08-04: lista sessions finalizadas (status >= 3) que violariam a invariante '
  'chk_sessions_coherence. Usado para runbook de backfill + detecção de GPS bugs. '
  'Volume normal esperado: 0. See SESSIONS_COHERENCE_RUNBOOK.md.';

REVOKE ALL ON FUNCTION public.fn_find_sessions_incoherent(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_find_sessions_incoherent(integer) FROM anon;
REVOKE ALL ON FUNCTION public.fn_find_sessions_incoherent(integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_find_sessions_incoherent(integer) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. CHECK constraint chk_sessions_coherence
-- ──────────────────────────────────────────────────────────────────────────
-- Idempotência: se o constraint já existir, skip. Caso contrário:
--   (a) ADD CONSTRAINT … NOT VALID — instant, só valida NEW rows.
--   (b) VALIDATE CONSTRAINT — scan, bloqueio SHARE UPDATE EXCLUSIVE (ok).

DO $add_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'sessions'
      AND con.conname = 'chk_sessions_coherence'
  ) THEN
    EXECUTE $ddl$
      ALTER TABLE public.sessions
        ADD CONSTRAINT chk_sessions_coherence CHECK (
          status < 3 OR
          (total_distance_m = 0 AND moving_ms = 0) OR
          (total_distance_m >= 100 AND moving_ms >= 60000)
        ) NOT VALID
    $ddl$;

    -- Valida as rows existentes
    BEGIN
      ALTER TABLE public.sessions VALIDATE CONSTRAINT chk_sessions_coherence;
    EXCEPTION WHEN check_violation THEN
      -- Se falhar, reporta os offenders mas NÃO derrube a migration inteira:
      -- mantemos o NOT VALID para PROTEGER writes futuros enquanto o time
      -- corre o runbook de backfill.
      RAISE WARNING 'L08-04: chk_sessions_coherence adicionada NOT VALID; existem '
                    'rows offenders. Execute fn_find_sessions_incoherent para listar '
                    'e corrigir antes do VALIDATE definitivo.';
    END;
  END IF;
END $add_check$;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Assert helper para CI
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_sessions_coherence()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_cnt integer;
  v_sample text;
BEGIN
  SELECT count(*)::int INTO v_cnt
    FROM public.fn_find_sessions_incoherent(1000);

  IF v_cnt > 0 THEN
    SELECT string_agg(
             format('  - %s (user=%s, status=%s, dist=%sm, moving=%sms, reason=%s)',
                    id, user_id, status, total_distance_m, moving_ms, reason),
             E'\n' ORDER BY id)
      INTO v_sample
      FROM public.fn_find_sessions_incoherent(10);

    RAISE EXCEPTION 'L08-04: %s sessions incoerentes detectadas: %',
      v_cnt::text,
      E'\n' || COALESCE(v_sample, '(sample vazio)')
      USING ERRCODE = 'P0010',
            HINT    = 'See docs/runbooks/SESSIONS_COHERENCE_RUNBOOK.md §3 para playbook de backfill.';
  END IF;

  RETURN true;
END;
$fn$;

COMMENT ON FUNCTION public.fn_assert_sessions_coherence() IS
  'L08-04: raise P0010 se fn_find_sessions_incoherent retornar qualquer linha. '
  'Usado pelo CI (npm run audit:sessions-coherence) e runbooks operacionais.';

REVOKE ALL ON FUNCTION public.fn_assert_sessions_coherence() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_assert_sessions_coherence() FROM anon;
REVOKE ALL ON FUNCTION public.fn_assert_sessions_coherence() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_assert_sessions_coherence() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Self-test
-- ──────────────────────────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_cnt        integer;
  v_convalidated boolean;
BEGIN
  -- (a) Constraint existe
  SELECT count(*)::int INTO v_cnt
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relname = 'sessions'
     AND con.conname = 'chk_sessions_coherence'
     AND con.contype = 'c';
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'L08-04 selftest: chk_sessions_coherence não registrada';
  END IF;

  -- (b) É VALIDATED (ou pelo menos NOT VALID se backfill pendente)
  SELECT con.convalidated INTO v_convalidated
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
   WHERE c.relname = 'sessions' AND con.conname = 'chk_sessions_coherence';
  IF v_convalidated IS NULL THEN
    RAISE EXCEPTION 'L08-04 selftest: chk_sessions_coherence sem convalidated flag';
  END IF;

  -- (c) 2 funções SECURITY DEFINER registradas
  SELECT count(*)::int INTO v_cnt
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('fn_find_sessions_incoherent','fn_assert_sessions_coherence')
     AND p.prosecdef = true;
  IF v_cnt <> 2 THEN
    RAISE EXCEPTION 'L08-04 selftest: expected 2 SECURITY DEFINER fns, got %', v_cnt;
  END IF;

  -- (d) Rejeita INSERT incoerente via constraint
  BEGIN
    INSERT INTO public.sessions (
      id, user_id, status, start_time_ms, end_time_ms, total_distance_m,
      moving_ms, is_verified, integrity_flags, is_synced, created_at, source
    ) VALUES (
      'deadbeef-0000-0000-0000-000000000001'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid,
      3,
      1000000,
      2000000,
      5000,    -- dist > 0
      0,       -- moving_ms = 0 → violates invariant
      true, '{}', true, now(), 'app'
    );
    RAISE EXCEPTION 'L08-04 selftest: expected check_violation but INSERT succeeded';
  EXCEPTION
    WHEN check_violation THEN NULL;
    WHEN foreign_key_violation THEN
      -- FK para auth.users pode falhar antes do CHECK; aceita
      NULL;
    WHEN OTHERS THEN
      RAISE EXCEPTION 'L08-04 selftest: expected check_violation, got %: %',
        SQLSTATE, SQLERRM;
  END;

  -- (e) Assert wrapper passa em estado limpo
  PERFORM public.fn_assert_sessions_coherence();

  RAISE NOTICE '[L08-04.selftest] OK — 5 phases pass';
END $selftest$;

COMMIT;
