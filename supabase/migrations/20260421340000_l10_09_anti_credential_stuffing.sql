-- ============================================================================
-- L10-09 — Anti credential stuffing (email-scoped login throttle)
-- ============================================================================
--
-- Finding (docs/audit/findings/L10-09-falta-defesa-anti-credential-stuffing-no-mobile-portal.md):
--   Supabase Auth only rate-limits by IP. A distributed attacker can test
--   `1k emails × one common password` from a botnet and the per-IP limit
--   never triggers (each IP makes 1 request). Defender needs a
--   throttle keyed by **email** so credential stuffing hits a wall.
--
-- Design:
--   (1) `public.auth_login_attempts` — append-mostly table, one row per
--       (email_hash, window_start_minute). Email is NEVER stored raw;
--       only the SHA-256 hex (64 chars) lands here. CHECK enforces the
--       shape. Sliding window = last 15 minutes (configurable).
--
--   (2) `public.auth_login_throttle_config` — single-row tunable config
--       (fail_threshold_captcha, fail_threshold_block, window_seconds,
--       block_seconds). RLS forced, service_role only. Operator tweaks
--       thresholds without shipping code.
--
--   (3) Primitives (all SECURITY DEFINER, service_role only):
--       * `fn_login_throttle_record_failure(email_hash, ip)` — upserts the
--         attempt counter, returns jsonb `{attempts, requires_captcha,
--         locked, locked_until, reason}`. The edge function or portal
--         handler MUST gate the next auth attempt on
--         `requires_captcha=true` (render hCaptcha) or `locked=true`
--         (403 "try again later").
--       * `fn_login_throttle_record_success(email_hash)` — resets the
--         counter for that email, called after Supabase Auth returns
--         200.
--       * `fn_login_throttle_probe(email_hash)` — read-only shape as
--         `record_failure` without mutating; used by the UI to show
--         "X attempts remaining" without penalising the request itself.
--       * `fn_login_throttle_cleanup()` — purges rows older than
--         `window_seconds * 4`; scheduled via `pg_cron` (when available).
--
--   (4) CI: `npm run audit:anti-credential-stuffing` invokes
--       `fn_login_throttle_assert_shape()` which raises P0010 if the
--       table/config/primitives drifted (wrong columns, missing RLS,
--       helpers missing, anon has EXECUTE, …).
--
-- Callers (expected wiring; this migration only lays the foundation):
--   * `supabase/functions/login-pre-check/index.ts` (to be added in a
--     follow-up PR): invoked by the Flutter app + portal BEFORE sending
--     the actual credentials. Computes `email_hash`, calls
--     `fn_login_throttle_probe`, short-circuits with 429 or CAPTCHA if
--     needed.
--   * Same Edge Function calls `fn_login_throttle_record_failure` on
--     Supabase Auth's 400/401 path and `fn_login_throttle_record_success`
--     on 200.
--
-- Privacy:
--   * `email_hash` is a SHA-256 of `lower(trim(email))`. Irreversible.
--   * `ip` is stored as `inet` ONLY for the last N attempts per email
--     (L10-09 follow-up can add per-IP burst detection). The CHECK
--     allows NULL so the portal can omit it in strict-privacy mode.
--   * No raw email / password / user_id leaks into this table.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. auth_login_throttle_config (single-row tunable settings)
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.auth_login_throttle_config (
  id                        smallint PRIMARY KEY DEFAULT 1,
  fail_threshold_captcha    smallint NOT NULL DEFAULT 3,
  fail_threshold_block      smallint NOT NULL DEFAULT 10,
  window_seconds            integer  NOT NULL DEFAULT 900,
  block_seconds             integer  NOT NULL DEFAULT 900,
  updated_at                timestamptz NOT NULL DEFAULT now(),
  updated_by                uuid,
  CONSTRAINT chk_auth_throttle_singleton      CHECK (id = 1),
  CONSTRAINT chk_auth_throttle_captcha_range  CHECK (fail_threshold_captcha BETWEEN 1 AND 50),
  CONSTRAINT chk_auth_throttle_block_range    CHECK (fail_threshold_block BETWEEN 2 AND 200),
  CONSTRAINT chk_auth_throttle_block_gt_captcha
    CHECK (fail_threshold_block > fail_threshold_captcha),
  CONSTRAINT chk_auth_throttle_window_range
    CHECK (window_seconds BETWEEN 60 AND 86400),
  CONSTRAINT chk_auth_throttle_block_secs_range
    CHECK (block_seconds BETWEEN 60 AND 86400)
);

ALTER TABLE public.auth_login_throttle_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auth_login_throttle_config FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auth_login_throttle_config_service_rw
  ON public.auth_login_throttle_config;
CREATE POLICY auth_login_throttle_config_service_rw
  ON public.auth_login_throttle_config
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

INSERT INTO public.auth_login_throttle_config (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE public.auth_login_throttle_config IS
  'L10-09: single-row tunable config for email-scoped login throttle. '
  'Fail thresholds and window are the operator knobs. RLS forced, '
  'service_role only.';

-- ──────────────────────────────────────────────────────────────────────────
-- 2. auth_login_attempts (append-mostly counter)
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.auth_login_attempts (
  email_hash   text        NOT NULL,
  window_start timestamptz NOT NULL,
  attempts     integer     NOT NULL DEFAULT 0,
  last_ip      inet,
  last_attempt_at timestamptz NOT NULL DEFAULT now(),
  locked_until timestamptz,
  captcha_required_at timestamptz,
  PRIMARY KEY (email_hash, window_start),
  CONSTRAINT chk_auth_login_attempts_email_hash_shape
    CHECK (email_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT chk_auth_login_attempts_attempts_nn
    CHECK (attempts >= 0)
);

CREATE INDEX IF NOT EXISTS idx_auth_login_attempts_email_recent
  ON public.auth_login_attempts (email_hash, window_start DESC);

CREATE INDEX IF NOT EXISTS idx_auth_login_attempts_locked
  ON public.auth_login_attempts (locked_until DESC)
  WHERE locked_until IS NOT NULL;

ALTER TABLE public.auth_login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auth_login_attempts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auth_login_attempts_service_rw
  ON public.auth_login_attempts;
CREATE POLICY auth_login_attempts_service_rw
  ON public.auth_login_attempts
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.auth_login_attempts IS
  'L10-09: one row per (email_hash, window_start) — sliding-window '
  'counter against credential stuffing. email_hash is SHA-256 hex '
  '(64 chars). RLS forced, service_role only.';

-- ──────────────────────────────────────────────────────────────────────────
-- 3. fn_login_throttle_window_start (helper aligning `now()` to window)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_login_throttle_window_start(
  p_window_seconds integer
)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT to_timestamp(
    floor(extract(epoch FROM now()) / p_window_seconds) * p_window_seconds
  );
$$;

COMMENT ON FUNCTION public.fn_login_throttle_window_start(integer) IS
  'L10-09: aligns now() to the fixed-sized window used by the throttle. '
  'Shared by record_failure/probe/cleanup so counters bucket consistently.';

-- ──────────────────────────────────────────────────────────────────────────
-- 4. fn_login_throttle_record_failure
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_login_throttle_record_failure(
  p_email_hash text,
  p_ip         inet DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cfg  public.auth_login_throttle_config%ROWTYPE;
  v_ws   timestamptz;
  v_row  public.auth_login_attempts%ROWTYPE;
  v_total_attempts integer;
  v_requires_captcha boolean;
  v_locked boolean;
  v_locked_until timestamptz;
  v_captcha_at timestamptz;
BEGIN
  IF p_email_hash IS NULL OR p_email_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'L10-09: p_email_hash must be a lowercase SHA-256 hex string (64 chars)'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_cfg FROM public.auth_login_throttle_config WHERE id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L10-09: auth_login_throttle_config missing singleton row'
      USING ERRCODE = 'P0010';
  END IF;

  v_ws := public.fn_login_throttle_window_start(v_cfg.window_seconds);

  INSERT INTO public.auth_login_attempts
    (email_hash, window_start, attempts, last_ip, last_attempt_at)
  VALUES
    (p_email_hash, v_ws, 1, p_ip, now())
  ON CONFLICT (email_hash, window_start) DO UPDATE
    SET attempts = public.auth_login_attempts.attempts + 1,
        last_ip  = COALESCE(EXCLUDED.last_ip, public.auth_login_attempts.last_ip),
        last_attempt_at = now()
  RETURNING * INTO v_row;

  SELECT COALESCE(SUM(attempts), 0)::integer
  INTO v_total_attempts
  FROM public.auth_login_attempts
  WHERE email_hash = p_email_hash
    AND window_start >= v_ws - make_interval(secs => v_cfg.window_seconds);

  v_requires_captcha := v_total_attempts >= v_cfg.fail_threshold_captcha;
  v_locked := v_total_attempts >= v_cfg.fail_threshold_block;

  IF v_locked THEN
    v_locked_until := now() + make_interval(secs => v_cfg.block_seconds);
  END IF;

  IF v_requires_captcha THEN
    v_captcha_at := COALESCE(v_row.captcha_required_at, now());
  END IF;

  UPDATE public.auth_login_attempts
  SET locked_until        = COALESCE(v_locked_until, locked_until),
      captcha_required_at = COALESCE(v_captcha_at, captcha_required_at)
  WHERE email_hash = p_email_hash
    AND window_start = v_ws;

  RETURN jsonb_build_object(
    'attempts', v_total_attempts,
    'requires_captcha', v_requires_captcha,
    'locked', v_locked,
    'locked_until', v_locked_until,
    'window_start', v_ws,
    'window_seconds', v_cfg.window_seconds,
    'fail_threshold_captcha', v_cfg.fail_threshold_captcha,
    'fail_threshold_block', v_cfg.fail_threshold_block
  );
END;
$$;

COMMENT ON FUNCTION public.fn_login_throttle_record_failure(text, inet) IS
  'L10-09: records a failed login attempt for email_hash and returns '
  '{attempts, requires_captcha, locked, locked_until, ...}. Caller MUST '
  'gate the next auth attempt on requires_captcha/locked.';

REVOKE ALL ON FUNCTION public.fn_login_throttle_record_failure(text, inet) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_login_throttle_record_failure(text, inet) FROM anon;
REVOKE ALL ON FUNCTION public.fn_login_throttle_record_failure(text, inet) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_login_throttle_record_failure(text, inet) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. fn_login_throttle_record_success
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_login_throttle_record_success(
  p_email_hash text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_email_hash IS NULL OR p_email_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'L10-09: p_email_hash must be a lowercase SHA-256 hex string (64 chars)'
      USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.auth_login_attempts WHERE email_hash = p_email_hash;
END;
$$;

COMMENT ON FUNCTION public.fn_login_throttle_record_success(text) IS
  'L10-09: clears all attempt counters for email_hash after a successful '
  'login (Supabase Auth returned 200). Keeps the table small and '
  'eliminates residual CAPTCHA/lock state for legitimate users.';

REVOKE ALL ON FUNCTION public.fn_login_throttle_record_success(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_login_throttle_record_success(text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_login_throttle_record_success(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_login_throttle_record_success(text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 6. fn_login_throttle_probe (read-only)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_login_throttle_probe(
  p_email_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cfg  public.auth_login_throttle_config%ROWTYPE;
  v_ws   timestamptz;
  v_total integer;
  v_locked_until timestamptz;
  v_captcha_at timestamptz;
BEGIN
  IF p_email_hash IS NULL OR p_email_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'L10-09: p_email_hash must be a lowercase SHA-256 hex string (64 chars)'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_cfg FROM public.auth_login_throttle_config WHERE id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L10-09: auth_login_throttle_config missing singleton row'
      USING ERRCODE = 'P0010';
  END IF;

  v_ws := public.fn_login_throttle_window_start(v_cfg.window_seconds);

  SELECT COALESCE(SUM(attempts), 0)::integer,
         MAX(locked_until),
         MIN(captcha_required_at)
  INTO v_total, v_locked_until, v_captcha_at
  FROM public.auth_login_attempts
  WHERE email_hash = p_email_hash
    AND window_start >= v_ws - make_interval(secs => v_cfg.window_seconds);

  RETURN jsonb_build_object(
    'attempts', v_total,
    'requires_captcha', v_total >= v_cfg.fail_threshold_captcha,
    'locked', v_locked_until IS NOT NULL AND v_locked_until > now(),
    'locked_until', v_locked_until,
    'captcha_required_at', v_captcha_at,
    'window_start', v_ws,
    'window_seconds', v_cfg.window_seconds,
    'fail_threshold_captcha', v_cfg.fail_threshold_captcha,
    'fail_threshold_block', v_cfg.fail_threshold_block
  );
END;
$$;

COMMENT ON FUNCTION public.fn_login_throttle_probe(text) IS
  'L10-09: read-only view of the current throttle state for email_hash. '
  'Does not mutate — safe to call from UI "attempts remaining" banners.';

REVOKE ALL ON FUNCTION public.fn_login_throttle_probe(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_login_throttle_probe(text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_login_throttle_probe(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_login_throttle_probe(text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 7. fn_login_throttle_cleanup (run via pg_cron when available)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_login_throttle_cleanup()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cfg public.auth_login_throttle_config%ROWTYPE;
  v_cutoff timestamptz;
  v_deleted integer;
BEGIN
  SELECT * INTO v_cfg FROM public.auth_login_throttle_config WHERE id = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L10-09: auth_login_throttle_config missing singleton row'
      USING ERRCODE = 'P0010';
  END IF;

  v_cutoff := now() - make_interval(secs => v_cfg.window_seconds * 4);

  DELETE FROM public.auth_login_attempts
  WHERE window_start < v_cutoff
    AND (locked_until IS NULL OR locked_until < now());

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.fn_login_throttle_cleanup() IS
  'L10-09: purges attempt rows older than window_seconds*4 and whose '
  'lockout (if any) has expired. Safe to call hourly via pg_cron.';

REVOKE ALL ON FUNCTION public.fn_login_throttle_cleanup() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_login_throttle_cleanup() FROM anon;
REVOKE ALL ON FUNCTION public.fn_login_throttle_cleanup() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_login_throttle_cleanup() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 8. fn_login_throttle_assert_shape (CI guard helper)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_login_throttle_assert_shape()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_missing text[] := ARRAY[]::text[];
  v_anon_exec boolean;
BEGIN
  IF to_regclass('public.auth_login_attempts') IS NULL THEN
    v_missing := v_missing || 'table:public.auth_login_attempts';
  END IF;
  IF to_regclass('public.auth_login_throttle_config') IS NULL THEN
    v_missing := v_missing || 'table:public.auth_login_throttle_config';
  END IF;

  IF to_regprocedure('public.fn_login_throttle_record_failure(text,inet)') IS NULL THEN
    v_missing := v_missing || 'fn:fn_login_throttle_record_failure(text,inet)';
  END IF;
  IF to_regprocedure('public.fn_login_throttle_record_success(text)') IS NULL THEN
    v_missing := v_missing || 'fn:fn_login_throttle_record_success(text)';
  END IF;
  IF to_regprocedure('public.fn_login_throttle_probe(text)') IS NULL THEN
    v_missing := v_missing || 'fn:fn_login_throttle_probe(text)';
  END IF;
  IF to_regprocedure('public.fn_login_throttle_cleanup()') IS NULL THEN
    v_missing := v_missing || 'fn:fn_login_throttle_cleanup()';
  END IF;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'L10-09: anti-credential-stuffing primitives missing: %', array_to_string(v_missing, ', ')
      USING ERRCODE = 'P0010',
            HINT    = 'Apply migration 20260421340000_l10_09_anti_credential_stuffing.sql.';
  END IF;

  SELECT NOT relrowsecurity OR NOT relforcerowsecurity
  INTO v_anon_exec
  FROM pg_class
  WHERE oid = 'public.auth_login_attempts'::regclass;
  IF v_anon_exec THEN
    RAISE EXCEPTION 'L10-09: auth_login_attempts RLS not forced'
      USING ERRCODE = 'P0010';
  END IF;

  SELECT NOT relrowsecurity OR NOT relforcerowsecurity
  INTO v_anon_exec
  FROM pg_class
  WHERE oid = 'public.auth_login_throttle_config'::regclass;
  IF v_anon_exec THEN
    RAISE EXCEPTION 'L10-09: auth_login_throttle_config RLS not forced'
      USING ERRCODE = 'P0010';
  END IF;

  SELECT has_function_privilege('anon', 'public.fn_login_throttle_record_failure(text,inet)', 'EXECUTE')
      OR has_function_privilege('anon', 'public.fn_login_throttle_probe(text)', 'EXECUTE')
      OR has_function_privilege('anon', 'public.fn_login_throttle_record_success(text)', 'EXECUTE')
  INTO v_anon_exec;
  IF v_anon_exec THEN
    RAISE EXCEPTION 'L10-09: anon has EXECUTE on throttle primitives — tighten grants'
      USING ERRCODE = 'P0010';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.fn_login_throttle_assert_shape() IS
  'L10-09: raises P0010 when any of the credential-stuffing defences '
  'drift (missing table/function, RLS relaxed, anon grants). Used by '
  'npm run audit:anti-credential-stuffing.';

REVOKE ALL ON FUNCTION public.fn_login_throttle_assert_shape() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_login_throttle_assert_shape() FROM anon;
REVOKE ALL ON FUNCTION public.fn_login_throttle_assert_shape() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_login_throttle_assert_shape() TO service_role;

COMMIT;

-- ============================================================================
-- Self-test (separate transaction; visible errors abort the migration)
-- ============================================================================
DO $L10_09_selftest$
DECLARE
  v_hash text := encode(digest('l10.09.selftest@omnirunner.local', 'sha256'), 'hex');
  v_res  jsonb;
BEGIN
  PERFORM public.fn_login_throttle_assert_shape();

  BEGIN
    PERFORM public.fn_login_throttle_record_failure('not-a-hash', NULL);
    RAISE EXCEPTION 'L10-09 selftest: record_failure accepted invalid hash';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  DELETE FROM public.auth_login_attempts WHERE email_hash = v_hash;

  v_res := public.fn_login_throttle_record_failure(v_hash, NULL);
  IF (v_res->>'attempts')::int <> 1 THEN
    RAISE EXCEPTION 'L10-09 selftest: first failure did not count as 1 (got %)', v_res;
  END IF;
  IF (v_res->>'requires_captcha')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'L10-09 selftest: first failure should not require captcha (got %)', v_res;
  END IF;

  PERFORM public.fn_login_throttle_record_failure(v_hash, NULL);
  PERFORM public.fn_login_throttle_record_failure(v_hash, NULL);
  v_res := public.fn_login_throttle_probe(v_hash);
  IF (v_res->>'attempts')::int < 3 THEN
    RAISE EXCEPTION 'L10-09 selftest: expected attempts>=3, got %', v_res;
  END IF;
  IF (v_res->>'requires_captcha')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'L10-09 selftest: expected requires_captcha=true at 3 attempts, got %', v_res;
  END IF;

  PERFORM public.fn_login_throttle_record_success(v_hash);
  IF EXISTS (SELECT 1 FROM public.auth_login_attempts WHERE email_hash = v_hash) THEN
    RAISE EXCEPTION 'L10-09 selftest: record_success did not clear the counters';
  END IF;

  RAISE NOTICE '[L10-09.selftest] OK — anti credential stuffing primitives behave correctly';
END
$L10_09_selftest$;
