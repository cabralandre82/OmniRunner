-- ============================================================================
-- L04-06 — Social handle policy (instagram / tiktok) + rate limit
-- Date: 2026-04-21
-- ============================================================================
-- `profiles.instagram_handle` and `profiles.tiktok_handle` ship today with
-- zero validation and zero visibility policy. The finder called out three
-- risks:
--
--   1. Handle values accept any UTF-8 string — including @bit.ly/xyz or
--      https://... links that can be weaponised for phishing.
--   2. The handle is glued to `display_name` visibility, so athletes can't
--      surface their display name to the public without also exposing their
--      socials — a concrete stalking / harassment vector.
--   3. No rate limit on handle changes, so an attacker can rotate the handle
--      every 10 s to defeat anti-impersonation cross-checks.
--
-- This migration ships the canonical primitives:
--
--   a) CHECK-bound format validation on `instagram_handle` and
--      `tiktok_handle` (strict handle-only, length-limited, no links).
--   b) `profiles.profile_public jsonb` default
--        `{"show_instagram":false,"show_tiktok":false,"show_pace":false,
--          "show_location":false}`
--      (privacy-first: no social exposure unless the owner opts in).
--   c) `profiles.social_handles_updated_at` timestamp column.
--   d) BEFORE UPDATE trigger `fn_profiles_social_handles_rate_limit` —
--      rejects a change to either handle if the previous change was less
--      than 24 h ago (waived for service_role so platform_admin remediation
--      still works), and logs every accepted handle change to
--      `public.portal_audit_log` for anti-impersonation investigation.
--   e) `fn_public_profile_view(target uuid)` — STABLE SECURITY DEFINER
--      viewer-scoped accessor that honours `profile_public` flags: the
--      owner receives the raw handle, everyone else receives NULL when the
--      owner did not tick the corresponding `show_*` flag.
--   f) `fn_validate_social_handle(text)` IMMUTABLE helper used from the
--      CHECK constraint (single source of truth; the regex is asserted
--      from the self-test block).
--
-- Rate-limit window is expressed via the canonical constant
-- `app.social_handle_min_interval_seconds` (default 86400); operators can
-- override via `ALTER DATABASE <db> SET app.social_handle_min_interval_seconds
-- = N` without touching code.

BEGIN;

-- ── 0. helper: validator (used by CHECK and by self-test) ─────────────────
CREATE OR REPLACE FUNCTION public.fn_validate_social_handle(p_handle text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT
    p_handle IS NULL
    OR (
      length(p_handle) BETWEEN 1 AND 30
      AND p_handle ~ '^[A-Za-z0-9._]+$'
      AND p_handle NOT ILIKE '%http%'
      AND p_handle NOT ILIKE '%bit.ly%'
      AND p_handle NOT ILIKE '%//%'
    );
$$;

COMMENT ON FUNCTION public.fn_validate_social_handle(text) IS
  'L04-06: returns true when p_handle is NULL or a 1-30 char instagram/tiktok handle made of [A-Za-z0-9._] with no links/separators. Used from the CHECK constraint.';

-- ── 1. CHECK-bound format validation ─────────────────────────────────────
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_instagram_handle_format;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_instagram_handle_format
  CHECK (public.fn_validate_social_handle(instagram_handle));

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_tiktok_handle_format;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_tiktok_handle_format
  CHECK (public.fn_validate_social_handle(tiktok_handle));

-- ── 2. profiles.profile_public jsonb ─────────────────────────────────────
DO $add_col$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='profile_public'
  ) THEN
    RAISE NOTICE 'profiles.profile_public already exists — skipping';
  ELSE
    ALTER TABLE public.profiles
      ADD COLUMN profile_public jsonb NOT NULL
      DEFAULT '{"show_instagram":false,"show_tiktok":false,"show_pace":false,"show_location":false}'::jsonb;
  END IF;
END
$add_col$;

CREATE OR REPLACE FUNCTION public.fn_validate_profile_public(p_public jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT
    p_public IS NOT NULL
    AND jsonb_typeof(p_public) = 'object'
    AND p_public ? 'show_instagram'
    AND p_public ? 'show_tiktok'
    AND p_public ? 'show_pace'
    AND p_public ? 'show_location'
    AND jsonb_typeof(p_public->'show_instagram') = 'boolean'
    AND jsonb_typeof(p_public->'show_tiktok')    = 'boolean'
    AND jsonb_typeof(p_public->'show_pace')      = 'boolean'
    AND jsonb_typeof(p_public->'show_location')  = 'boolean';
$$;

COMMENT ON FUNCTION public.fn_validate_profile_public(jsonb) IS
  'L04-06: IMMUTABLE shape validator for profiles.profile_public — must be an object with four boolean flags (show_instagram, show_tiktok, show_pace, show_location).';

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_profile_public_shape;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_profile_public_shape
  CHECK (public.fn_validate_profile_public(profile_public));

COMMENT ON COLUMN public.profiles.profile_public IS
  'L04-06: granular public-visibility flags. Privacy-first defaults (all false). Honoured by fn_public_profile_view and should be read by any public-profile surface.';

-- ── 3. profiles.social_handles_updated_at ───────────────────────────────
DO $add_ts$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='social_handles_updated_at'
  ) THEN
    RAISE NOTICE 'profiles.social_handles_updated_at already exists — skipping';
  ELSE
    ALTER TABLE public.profiles
      ADD COLUMN social_handles_updated_at timestamptz;
  END IF;
END
$add_ts$;

COMMENT ON COLUMN public.profiles.social_handles_updated_at IS
  'L04-06: last time instagram_handle or tiktok_handle was updated. Enforced min-interval by fn_profiles_social_handles_rate_limit.';

-- ── 4. BEFORE UPDATE rate-limit trigger ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_profiles_social_handles_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_now             timestamptz := now();
  v_min_interval_s  integer;
  v_setting         text;
  v_changed         boolean := false;
BEGIN
  -- service_role is waived to allow platform_admin remediation (impersonation
  -- takedowns etc) without the 24h knob getting in the way.
  IF current_setting('role', true) = 'service_role' THEN
    IF NEW.instagram_handle IS DISTINCT FROM OLD.instagram_handle
       OR NEW.tiktok_handle IS DISTINCT FROM OLD.tiktok_handle THEN
      NEW.social_handles_updated_at := v_now;
    END IF;
    RETURN NEW;
  END IF;

  v_changed :=
        NEW.instagram_handle IS DISTINCT FROM OLD.instagram_handle
    OR  NEW.tiktok_handle    IS DISTINCT FROM OLD.tiktok_handle;

  IF NOT v_changed THEN
    RETURN NEW;
  END IF;

  v_setting := current_setting('app.social_handle_min_interval_seconds', true);
  v_min_interval_s := COALESCE(NULLIF(v_setting, '')::integer, 86400);

  IF OLD.social_handles_updated_at IS NOT NULL
     AND (v_now - OLD.social_handles_updated_at)
           < make_interval(secs => v_min_interval_s) THEN
    RAISE EXCEPTION
      'social_handle.rate_limited: changes allowed once every % seconds (last change at %)',
      v_min_interval_s, OLD.social_handles_updated_at
      USING ERRCODE = 'P0001';
  END IF;

  NEW.social_handles_updated_at := v_now;

  -- anti-impersonation audit (best-effort; audit failures do not block the
  -- write because the CHECK constraint already prevents weaponised payloads)
  BEGIN
    INSERT INTO public.portal_audit_log (
      actor_id, group_id, action, target_type, target_id, metadata
    ) VALUES (
      COALESCE(auth.uid(), OLD.id),
      NULL,
      'profile.social_handle_changed',
      'profile',
      NEW.id,
      jsonb_build_object(
        'instagram_old', OLD.instagram_handle,
        'instagram_new', NEW.instagram_handle,
        'tiktok_old',    OLD.tiktok_handle,
        'tiktok_new',    NEW.tiktok_handle
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'L04-06: failed to write portal_audit_log social_handle_changed for profile %: % / %', NEW.id, SQLSTATE, SQLERRM;
  END;

  RETURN NEW;
END
$$;

COMMENT ON FUNCTION public.fn_profiles_social_handles_rate_limit() IS
  'L04-06: enforces min-interval on instagram/tiktok handle changes (default 24h), records every accepted change in portal_audit_log, and waives the rate limit for service_role.';

DROP TRIGGER IF EXISTS trg_profiles_social_handles_rate_limit ON public.profiles;
CREATE TRIGGER trg_profiles_social_handles_rate_limit
  BEFORE UPDATE OF instagram_handle, tiktok_handle ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_profiles_social_handles_rate_limit();

-- ── 5. viewer-scoped public profile accessor ─────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_public_profile_view(p_target uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer  uuid := auth.uid();
  v_row     public.profiles%ROWTYPE;
  v_flags   jsonb;
  v_self    boolean;
  v_admin   boolean;
BEGIN
  IF p_target IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_row FROM public.profiles WHERE id = p_target;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_flags := v_row.profile_public;
  v_self  := v_viewer IS NOT NULL AND v_viewer = p_target;
  v_admin := v_viewer IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = v_viewer AND p.platform_role = 'admin'
  );

  RETURN jsonb_build_object(
    'id',                p_target,
    'display_name',      v_row.display_name,
    'avatar_url',        v_row.avatar_url,
    'instagram_handle',
      CASE WHEN v_self OR v_admin
               OR COALESCE((v_flags->>'show_instagram')::boolean, false)
           THEN v_row.instagram_handle ELSE NULL END,
    'tiktok_handle',
      CASE WHEN v_self OR v_admin
               OR COALESCE((v_flags->>'show_tiktok')::boolean, false)
           THEN v_row.tiktok_handle ELSE NULL END,
    'show_pace',     COALESCE((v_flags->>'show_pace')::boolean, false),
    'show_location', COALESCE((v_flags->>'show_location')::boolean, false),
    'viewer_is_self', v_self,
    'viewer_is_admin', v_admin
  );
END
$$;

COMMENT ON FUNCTION public.fn_public_profile_view(uuid) IS
  'L04-06: viewer-scoped public profile accessor. Handles are surfaced only when viewer = owner / platform_admin / owner explicitly toggled the corresponding show_* flag. show_pace + show_location are returned so downstream feeds can honour them without re-reading profiles.';

-- ── 6. self-test ──────────────────────────────────────────────────────────
DO $selftest$
BEGIN
  -- validator positives
  IF NOT public.fn_validate_social_handle(NULL) THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle(NULL) must be TRUE';
  END IF;
  IF NOT public.fn_validate_social_handle('omni_runner') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle must accept "omni_runner"';
  END IF;
  IF NOT public.fn_validate_social_handle('a.b_c1') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle must accept "a.b_c1"';
  END IF;

  -- validator negatives
  IF public.fn_validate_social_handle('') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle("") must be FALSE';
  END IF;
  IF public.fn_validate_social_handle('bit.ly/xyz') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle must reject bit.ly payloads';
  END IF;
  IF public.fn_validate_social_handle('https://evil.example/x') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle must reject http(s) payloads';
  END IF;
  IF public.fn_validate_social_handle('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle must reject >30-char payloads';
  END IF;
  IF public.fn_validate_social_handle('has space') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle must reject whitespace';
  END IF;
  IF public.fn_validate_social_handle('with/slash') THEN
    RAISE EXCEPTION 'self-test: fn_validate_social_handle must reject slashes';
  END IF;

  -- profile_public validator
  IF NOT public.fn_validate_profile_public(
       '{"show_instagram":false,"show_tiktok":false,"show_pace":false,"show_location":false}'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_profile_public must accept default shape';
  END IF;
  IF public.fn_validate_profile_public('{"show_instagram":1}'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_profile_public must reject wrong type';
  END IF;
  IF public.fn_validate_profile_public('{}'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_profile_public must reject missing keys';
  END IF;

  RAISE NOTICE 'L04-06 self-test passed';
END
$selftest$;

-- ── 7. grants ──────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.fn_validate_social_handle(text)      TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_validate_profile_public(jsonb)    TO PUBLIC;
REVOKE ALL ON FUNCTION public.fn_public_profile_view(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_public_profile_view(uuid)
  TO authenticated, service_role, anon;

COMMIT;
