-- L12-07 + L07-06: per-user timezone awareness for onboarding-nudge-daily
--
-- Problem (L12-07):
--   pg_cron runs `onboarding-nudge-daily` at 10:00 UTC = 07:00 BRT, too
--   early for push notifications targeting Brazilian users (the audit
--   explicitly notes "07:00 BRT may be too early"). Worse, users in
--   other timezones (North-East Brazil islands, European coaches, US
--   assessorias) get one-size-fits-all UTC-tied timing.
--
-- Problem (L07-06):
--   `profiles` has no timezone column. `sessions.start_time_ms` is
--   stored UTC and formatted client-side — acceptable on the mobile app
--   but not for server-side jobs that want "send at 09:00 local" or
--   "close the day at 23:59:59 local".
--
-- Fix strategy:
--   1. `profiles.timezone text NOT NULL DEFAULT 'America/Sao_Paulo'`
--      with a CHECK validating the IANA name via `now() AT TIME ZONE`.
--      Default is BR-first (product-strategic); onboarding flow may
--      detect browser TZ and UPDATE to the correct value later.
--   2. `profiles.notification_hour_local smallint NOT NULL DEFAULT 9`
--      CHECK 0..23 — the hour-of-day (user's local time) at which they
--      want to receive onboarding nudges and similar "daily push" rules.
--      9 = "after morning commute, before standup".
--   3. `public.fn_user_local_hour(uuid) RETURNS smallint` STABLE helper
--      that returns the user's current hour-of-day in their configured
--      TZ. Enables SQL-side filtering when we eventually partition the
--      nudge job into per-hour chunks.
--   4. `public.fn_should_send_nudge_now(uuid, smallint) RETURNS boolean`
--      convenience wrapper — TRUE iff `fn_user_local_hour(u)` equals the
--      user's preferred hour (or the override passed in).
--   5. Reschedule `onboarding-nudge-daily` from `0 10 * * *` to
--      `0 * * * *` (hourly). The Edge Function then checks each user's
--      local hour and only dispatches when it matches the user's
--      preferred hour. L12-09 dedup (UNIQUE on (user_id, rule, context_id)
--      with context_id = "d${daysSinceRegistration}") already guarantees
--      one push per day per user even if the hourly loop runs 24×.
--   6. Rename the cron job from "onboarding-nudge-daily" to
--      "onboarding-nudge-hourly" to reflect reality. The old name is
--      unscheduled cleanly if present; cron_run_state gets a new row.
--
-- This migration is additive, idempotent, and backwards compatible:
--   - default TZ matches existing implicit assumption (BRT),
--   - default hour 9 means everyone gets the nudge at 09:00 local after
--     the hourly cron kicks in,
--   - if profiles is missing `timezone` (fresh dev DB), the Edge
--     Function falls back to Sao_Paulo/9 gracefully.
--
-- Related: L07-06 (timezone column), L12-09 (idempotency), L12-08
-- (clearing-cron timezone — same pattern applied to settle job).

SET search_path = public, pg_catalog, pg_temp;
SET client_min_messages = warning;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema additions to public.profiles
-- ─────────────────────────────────────────────────────────────────────────────

DO $schema$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'profiles'
       AND column_name  = 'timezone'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN timezone text NOT NULL DEFAULT 'America/Sao_Paulo';
    COMMENT ON COLUMN public.profiles.timezone IS
      'IANA timezone (e.g. America/Sao_Paulo, Europe/Lisbon). '
      'Default assumes BR-first product; onboarding flow should detect '
      'browser TZ and UPDATE after first login. See L07-06/L12-07.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'profiles'
       AND column_name  = 'notification_hour_local'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN notification_hour_local smallint NOT NULL DEFAULT 9;
    COMMENT ON COLUMN public.profiles.notification_hour_local IS
      'Hour-of-day (0..23) in the user''s local timezone at which '
      'daily push rules (onboarding_nudge, streak_at_risk, inactivity_nudge) '
      'may fire. Defaults to 9. See L12-07.';
  END IF;
END$schema$;

-- Validate timezone via CHECK (rejects typos like "America/Sao Paulo").
-- Uses a function so the CHECK can probe `now() AT TIME ZONE ...` which
-- raises `22023 invalid_parameter_value` for unknown zones.
DO $check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.profiles'::regclass
       AND conname  = 'profiles_timezone_valid'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_timezone_valid
      CHECK (public.fn_is_valid_timezone(timezone));
  END IF;
EXCEPTION
  WHEN undefined_function THEN
    -- fn_is_valid_timezone installed below; the CHECK is re-added at
    -- the end of this migration after the function exists.
    NULL;
END$check$;

DO $check2$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.profiles'::regclass
       AND conname  = 'profiles_notification_hour_local_range'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_notification_hour_local_range
      CHECK (notification_hour_local BETWEEN 0 AND 23);
  END IF;
END$check2$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fn_is_valid_timezone — IANA timezone sanity check
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_is_valid_timezone(p_tz text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dummy timestamptz;
BEGIN
  IF p_tz IS NULL OR length(trim(p_tz)) = 0 THEN
    RETURN false;
  END IF;
  BEGIN
    v_dummy := (timestamp '2000-01-01 12:00:00') AT TIME ZONE p_tz;
    RETURN true;
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_is_valid_timezone(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_is_valid_timezone(text)
  TO authenticated, service_role;

-- Re-attempt adding the CHECK now that the function exists (idempotent).
DO $check_retry$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.profiles'::regclass
       AND conname  = 'profiles_timezone_valid'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_timezone_valid
      CHECK (public.fn_is_valid_timezone(timezone));
  END IF;
END$check_retry$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fn_user_local_hour — current hour-of-day in user's TZ
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_user_local_hour(p_user_id uuid)
RETURNS smallint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tz text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER_ID: p_user_id is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT timezone INTO v_tz
    FROM public.profiles
   WHERE id = p_user_id;

  IF v_tz IS NULL THEN
    v_tz := 'America/Sao_Paulo';
  END IF;

  BEGIN
    RETURN EXTRACT(HOUR FROM (now() AT TIME ZONE v_tz))::smallint;
  EXCEPTION WHEN OTHERS THEN
    -- Defensive fallback on a corrupt TZ string somehow bypassing the CHECK
    -- (e.g. extension swap). Never throw into callers that want a scalar.
    RETURN EXTRACT(HOUR FROM (now() AT TIME ZONE 'America/Sao_Paulo'))::smallint;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_user_local_hour(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_user_local_hour(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. fn_should_send_nudge_now — boolean convenience
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_should_send_nudge_now(
  p_user_id        uuid,
  p_preferred_hour smallint DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_pref   smallint;
  v_now_h  smallint;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER_ID: p_user_id is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_preferred_hour IS NOT NULL THEN
    IF p_preferred_hour < 0 OR p_preferred_hour > 23 THEN
      RAISE EXCEPTION 'INVALID_HOUR: p_preferred_hour must be in 0..23'
        USING ERRCODE = '22023';
    END IF;
    v_pref := p_preferred_hour;
  ELSE
    SELECT notification_hour_local INTO v_pref
      FROM public.profiles
     WHERE id = p_user_id;
    IF v_pref IS NULL THEN v_pref := 9; END IF;
  END IF;

  v_now_h := public.fn_user_local_hour(p_user_id);
  RETURN v_now_h = v_pref;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_should_send_nudge_now(uuid, smallint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_should_send_nudge_now(uuid, smallint) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Reschedule the onboarding-nudge cron from daily 10:00 UTC to hourly
-- ─────────────────────────────────────────────────────────────────────────────

DO $reschedule$
DECLARE
  v_cron_available boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) INTO v_cron_available;

  IF NOT v_cron_available THEN
    RAISE NOTICE '[L12-07] pg_cron not installed; skipping reschedule.';
    RETURN;
  END IF;

  -- Drop both the legacy name and any previous hourly rescheduling
  -- attempt, idempotent.
  BEGIN PERFORM cron.unschedule('onboarding-nudge-daily');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM cron.unschedule('onboarding-nudge-hourly');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- New hourly schedule. The Edge Function filters by each user's
  -- notification_hour_local, so 23 of 24 invocations are near-no-ops
  -- (just fetch recent profiles + skip loop); L12-09 dedup plus the
  -- date-bucketed context_id guarantees exactly-once per user per day.
  PERFORM cron.schedule(
    'onboarding-nudge-hourly',
    '0 * * * *',
    $cron$ SELECT public.fn_invoke_onboarding_nudge_safe(); $cron$
  );

  -- Keep cron_run_state tidy: insert a new row for the new name,
  -- leave the legacy row untouched (it now shows last_status='never_run'
  -- forever, which is an intentional historical marker).
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
     WHERE n.nspname = 'public' AND c.relname = 'cron_run_state'
  ) THEN
    INSERT INTO public.cron_run_state(name, last_status)
    VALUES ('onboarding-nudge-hourly', 'never_run')
    ON CONFLICT (name) DO NOTHING;
  END IF;

  RAISE NOTICE '[L12-07] onboarding-nudge cron rescheduled to hourly (0 * * * *)';
END$reschedule$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Self-test — validate install before release
-- ─────────────────────────────────────────────────────────────────────────────

DO $selftest$
DECLARE
  v_tz_col        boolean;
  v_hour_col      boolean;
  v_tz_check      boolean;
  v_hour_check    boolean;
  v_fn_valid      boolean;
  v_fn_local_hour boolean;
  v_fn_should     boolean;
  v_test_hour     smallint;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'profiles'
       AND column_name = 'timezone'
  ) INTO v_tz_col;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'profiles'
       AND column_name = 'notification_hour_local'
  ) INTO v_hour_col;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.profiles'::regclass
       AND conname  = 'profiles_timezone_valid'
  ) INTO v_tz_check;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.profiles'::regclass
       AND conname  = 'profiles_notification_hour_local_range'
  ) INTO v_hour_check;

  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'fn_is_valid_timezone'
  ) INTO v_fn_valid;

  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'fn_user_local_hour'
  ) INTO v_fn_local_hour;

  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'fn_should_send_nudge_now'
  ) INTO v_fn_should;

  IF NOT v_tz_col        THEN RAISE EXCEPTION 'L12-07: profiles.timezone column missing'; END IF;
  IF NOT v_hour_col      THEN RAISE EXCEPTION 'L12-07: profiles.notification_hour_local column missing'; END IF;
  IF NOT v_tz_check      THEN RAISE EXCEPTION 'L12-07: profiles_timezone_valid CHECK missing'; END IF;
  IF NOT v_hour_check    THEN RAISE EXCEPTION 'L12-07: profiles_notification_hour_local_range CHECK missing'; END IF;
  IF NOT v_fn_valid      THEN RAISE EXCEPTION 'L12-07: fn_is_valid_timezone not registered'; END IF;
  IF NOT v_fn_local_hour THEN RAISE EXCEPTION 'L12-07: fn_user_local_hour not registered'; END IF;
  IF NOT v_fn_should     THEN RAISE EXCEPTION 'L12-07: fn_should_send_nudge_now not registered'; END IF;

  -- Lightweight behavioural checks.
  IF NOT public.fn_is_valid_timezone('America/Sao_Paulo') THEN
    RAISE EXCEPTION 'L12-07: fn_is_valid_timezone rejects America/Sao_Paulo';
  END IF;
  IF public.fn_is_valid_timezone('Mars/Olympus') THEN
    RAISE EXCEPTION 'L12-07: fn_is_valid_timezone accepts bogus zone Mars/Olympus';
  END IF;
  IF public.fn_is_valid_timezone(NULL) THEN
    RAISE EXCEPTION 'L12-07: fn_is_valid_timezone accepts NULL';
  END IF;
  IF public.fn_is_valid_timezone('') THEN
    RAISE EXCEPTION 'L12-07: fn_is_valid_timezone accepts empty string';
  END IF;

  -- Argument validation
  BEGIN
    PERFORM public.fn_user_local_hour(NULL);
    RAISE EXCEPTION 'L12-07: fn_user_local_hour did not raise on NULL user_id';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  BEGIN
    PERFORM public.fn_should_send_nudge_now(
      '00000000-0000-0000-0000-000000000000'::uuid, 24::smallint);
    RAISE EXCEPTION 'L12-07: fn_should_send_nudge_now accepted hour=24';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- fn_user_local_hour for a non-existent user should still return a
  -- scalar (defaults to Sao_Paulo).
  v_test_hour := public.fn_user_local_hour(
    '00000000-0000-0000-0000-000000000000'::uuid);
  IF v_test_hour < 0 OR v_test_hour > 23 THEN
    RAISE EXCEPTION 'L12-07: fn_user_local_hour returned out-of-range %', v_test_hour;
  END IF;

  RAISE NOTICE '[L12-07.selftest] OK — all invariants pass (now=% hour, tz-check-passed)',
    v_test_hour;
END$selftest$;
