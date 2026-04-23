-- ============================================================================
-- L16-01 — White-label branding primitives per coaching_group
-- Date: 2026-04-21
-- ============================================================================
-- Current state: `public.portal_branding` exists since 2026-02-27 (portal CSS
-- only) with free-form TEXT columns for logo_url / primary_color / sidebar_bg
-- / sidebar_text / accent_color — no validation (any string accepted), no
-- public read surface (RLS requires coaching_members row, which blocks the
-- Flutter app showing the group's theme before join), no Flutter-specific
-- asset slots (logo_url_dark, favicon_url, brand_name), no feature flag
-- (always on once a group inserts a row), no audit trail on who/when the
-- branding was last edited.
--
-- The audit finding (L16-01) asks for real white-label: colour + logo + brand
-- name visible on both portal (CSS vars) and the Flutter client (ThemeData)
-- for any group that opted in. This migration keeps the canonical
-- `portal_branding` table and extends it:
--
--   1. Adds `brand_name`, `logo_url_dark`, `favicon_url`, `subtitle`
--      (visible in mobile splash / drawer), `branding_enabled` boolean
--      gate, `updated_by uuid` actor, and `version bigint` optimistic
--      counter.
--   2. Tightens validation via one IMMUTABLE helper + CHECK constraints:
--      - `fn_validate_hex_color(text)` — `^#[0-9A-Fa-f]{6}$` only.
--      - URL columns must start with `https://` and length ≤ 500.
--      - `brand_name` length 2-40; `subtitle` length ≤ 120.
--   3. New SECURITY DEFINER STABLE RPC `fn_group_branding_public(group_id)`
--      — viewer-scoped: returns the `visible` shape (only the branding_enabled
--      payload; null otherwise) without requiring `coaching_members` row,
--      so the mobile app can pull the theme on a public group page.
--   4. BEFORE UPDATE trigger `fn_portal_branding_version_bump` increments
--      `version`, stamps `updated_by = auth.uid()`, and appends the diff
--      to `portal_audit_log` under action `group.branding.updated`
--      (fail-open audit).
--   5. SECURITY DEFINER RPC `fn_group_branding_set(group_id, payload jsonb)`
--      — single atomic write surface that admin UI can call; validates all
--      fields via the helper, gates on `admin_master` membership (or
--      platform_role='admin'), and upserts.
--
-- No RLS change on existing policies (admin_master write, staff read,
-- platform_admin read are preserved). The new public accessor bypasses RLS
-- via SECURITY DEFINER but only returns sanitised data.
--
-- Additive only — no destructive column drop, no existing policy removal.

BEGIN;

-- ── 0. Extension column additions (idempotent) ───────────────────────────

ALTER TABLE public.portal_branding
  ADD COLUMN IF NOT EXISTS brand_name TEXT,
  ADD COLUMN IF NOT EXISTS subtitle TEXT,
  ADD COLUMN IF NOT EXISTS logo_url_dark TEXT,
  ADD COLUMN IF NOT EXISTS favicon_url TEXT,
  ADD COLUMN IF NOT EXISTS branding_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 0;

-- ── 1. Validation helpers ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_validate_hex_color(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
BEGIN
  IF p_value IS NULL THEN
    RETURN TRUE;
  END IF;
  RETURN p_value ~ '^#[0-9A-Fa-f]{6}$';
END;
$$;

COMMENT ON FUNCTION public.fn_validate_hex_color(TEXT) IS
  'Returns true when input is NULL or a canonical 6-digit hex colour (#RRGGBB). Used by portal_branding CHECK constraints.';

GRANT EXECUTE ON FUNCTION public.fn_validate_hex_color(TEXT) TO PUBLIC;

CREATE OR REPLACE FUNCTION public.fn_validate_https_url(p_value TEXT, p_max_len INT DEFAULT 500)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
BEGIN
  IF p_value IS NULL THEN
    RETURN TRUE;
  END IF;
  IF length(p_value) > p_max_len THEN
    RETURN FALSE;
  END IF;
  RETURN p_value ~ '^https://[A-Za-z0-9._~:/?#@!$&''()*+,;=%\-]+$';
END;
$$;

COMMENT ON FUNCTION public.fn_validate_https_url(TEXT, INT) IS
  'Returns true when input is NULL or an https-only URL within length budget. Used by portal_branding CHECK constraints.';

GRANT EXECUTE ON FUNCTION public.fn_validate_https_url(TEXT, INT) TO PUBLIC;

-- ── 2. Tighten CHECK constraints on portal_branding ──────────────────────

ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_primary_color_hex;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_sidebar_bg_hex;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_sidebar_text_hex;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_accent_color_hex;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_logo_url_https;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_logo_url_dark_https;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_favicon_url_https;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_brand_name_len;
ALTER TABLE public.portal_branding DROP CONSTRAINT IF EXISTS portal_branding_subtitle_len;

ALTER TABLE public.portal_branding
  ADD CONSTRAINT portal_branding_primary_color_hex CHECK (public.fn_validate_hex_color(primary_color)),
  ADD CONSTRAINT portal_branding_sidebar_bg_hex    CHECK (public.fn_validate_hex_color(sidebar_bg)),
  ADD CONSTRAINT portal_branding_sidebar_text_hex  CHECK (public.fn_validate_hex_color(sidebar_text)),
  ADD CONSTRAINT portal_branding_accent_color_hex  CHECK (public.fn_validate_hex_color(accent_color)),
  ADD CONSTRAINT portal_branding_logo_url_https    CHECK (public.fn_validate_https_url(logo_url, 500)),
  ADD CONSTRAINT portal_branding_logo_url_dark_https CHECK (public.fn_validate_https_url(logo_url_dark, 500)),
  ADD CONSTRAINT portal_branding_favicon_url_https CHECK (public.fn_validate_https_url(favicon_url, 500)),
  ADD CONSTRAINT portal_branding_brand_name_len    CHECK (brand_name IS NULL OR (length(trim(brand_name)) BETWEEN 2 AND 40)),
  ADD CONSTRAINT portal_branding_subtitle_len      CHECK (subtitle IS NULL OR length(subtitle) <= 120);

-- ── 3. BEFORE UPDATE trigger: version + updated_by + audit ───────────────

CREATE OR REPLACE FUNCTION public.fn_portal_branding_version_bump()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_actor UUID;
  v_diff JSONB := '{}'::jsonb;
BEGIN
  v_actor := auth.uid();

  NEW.version := COALESCE(OLD.version, 0) + 1;
  NEW.updated_at := now();
  IF v_actor IS NOT NULL THEN
    NEW.updated_by := v_actor;
  END IF;

  BEGIN
    IF NEW.primary_color IS DISTINCT FROM OLD.primary_color THEN
      v_diff := v_diff || jsonb_build_object(
        'primary_color',
        jsonb_build_object('old', OLD.primary_color, 'new', NEW.primary_color)
      );
    END IF;
    IF NEW.logo_url IS DISTINCT FROM OLD.logo_url THEN
      v_diff := v_diff || jsonb_build_object(
        'logo_url',
        jsonb_build_object('old', OLD.logo_url, 'new', NEW.logo_url)
      );
    END IF;
    IF NEW.branding_enabled IS DISTINCT FROM OLD.branding_enabled THEN
      v_diff := v_diff || jsonb_build_object(
        'branding_enabled',
        jsonb_build_object('old', OLD.branding_enabled, 'new', NEW.branding_enabled)
      );
    END IF;
    IF NEW.brand_name IS DISTINCT FROM OLD.brand_name THEN
      v_diff := v_diff || jsonb_build_object(
        'brand_name',
        jsonb_build_object('old', OLD.brand_name, 'new', NEW.brand_name)
      );
    END IF;

    IF v_diff <> '{}'::jsonb AND to_regclass('public.portal_audit_log') IS NOT NULL THEN
      INSERT INTO public.portal_audit_log (
        actor_id,
        group_id,
        action,
        metadata,
        created_at
      ) VALUES (
        v_actor,
        NEW.group_id,
        'group.branding.updated',
        jsonb_build_object(
          'version', NEW.version,
          'diff', v_diff
        ),
        now()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'portal_branding audit log failed: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_portal_branding_version_bump() IS
  'BEFORE UPDATE trigger on portal_branding: bumps version, stamps updated_by from auth.uid, writes diff to portal_audit_log (fail-open).';

DROP TRIGGER IF EXISTS portal_branding_version_bump ON public.portal_branding;
CREATE TRIGGER portal_branding_version_bump
  BEFORE UPDATE ON public.portal_branding
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_portal_branding_version_bump();

-- ── 4. Public viewer-scoped accessor ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_group_branding_public(p_group_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.portal_branding;
BEGIN
  IF p_group_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_row
  FROM public.portal_branding
  WHERE group_id = p_group_id;

  IF NOT FOUND OR v_row.branding_enabled IS DISTINCT FROM TRUE THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'group_id', v_row.group_id,
    'version', v_row.version,
    'brand_name', v_row.brand_name,
    'subtitle', v_row.subtitle,
    'logo_url', v_row.logo_url,
    'logo_url_dark', v_row.logo_url_dark,
    'favicon_url', v_row.favicon_url,
    'primary_color', v_row.primary_color,
    'sidebar_bg', v_row.sidebar_bg,
    'sidebar_text', v_row.sidebar_text,
    'accent_color', v_row.accent_color
  );
END;
$$;

COMMENT ON FUNCTION public.fn_group_branding_public(UUID) IS
  'Viewer-scoped public branding payload for a group. Returns NULL when branding_enabled is false or row missing. Safe for mobile/portal pre-join theming.';

REVOKE ALL ON FUNCTION public.fn_group_branding_public(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_group_branding_public(UUID) TO anon, authenticated, service_role;

-- ── 5. Admin mutation RPC ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_group_branding_set(
  p_group_id UUID,
  p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_is_admin BOOLEAN := FALSE;
  v_is_platform_admin BOOLEAN := FALSE;
  v_row public.portal_branding;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_GROUP' USING ERRCODE = 'P0001';
  END IF;
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD' USING ERRCODE = 'P0001';
  END IF;

  IF current_setting('role', true) = 'service_role' THEN
    v_is_admin := TRUE;
  ELSIF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  ELSE
    SELECT TRUE INTO v_is_platform_admin
    FROM public.profiles
    WHERE id = v_actor AND platform_role = 'admin';

    IF v_is_platform_admin THEN
      v_is_admin := TRUE;
    ELSE
      SELECT TRUE INTO v_is_admin
      FROM public.coaching_members
      WHERE group_id = p_group_id
        AND user_id = v_actor
        AND role = 'admin_master';
    END IF;
  END IF;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.portal_branding (
    group_id,
    brand_name,
    subtitle,
    logo_url,
    logo_url_dark,
    favicon_url,
    primary_color,
    sidebar_bg,
    sidebar_text,
    accent_color,
    branding_enabled,
    updated_by,
    updated_at
  ) VALUES (
    p_group_id,
    NULLIF(p_payload->>'brand_name', ''),
    NULLIF(p_payload->>'subtitle', ''),
    NULLIF(p_payload->>'logo_url', ''),
    NULLIF(p_payload->>'logo_url_dark', ''),
    NULLIF(p_payload->>'favicon_url', ''),
    COALESCE(NULLIF(p_payload->>'primary_color', ''), '#2563eb'),
    COALESCE(NULLIF(p_payload->>'sidebar_bg', ''), '#ffffff'),
    COALESCE(NULLIF(p_payload->>'sidebar_text', ''), '#111827'),
    COALESCE(NULLIF(p_payload->>'accent_color', ''), '#2563eb'),
    COALESCE((p_payload->>'branding_enabled')::boolean, FALSE),
    v_actor,
    now()
  )
  ON CONFLICT (group_id) DO UPDATE SET
    brand_name       = EXCLUDED.brand_name,
    subtitle         = EXCLUDED.subtitle,
    logo_url         = EXCLUDED.logo_url,
    logo_url_dark    = EXCLUDED.logo_url_dark,
    favicon_url      = EXCLUDED.favicon_url,
    primary_color    = EXCLUDED.primary_color,
    sidebar_bg       = EXCLUDED.sidebar_bg,
    sidebar_text     = EXCLUDED.sidebar_text,
    accent_color     = EXCLUDED.accent_color,
    branding_enabled = EXCLUDED.branding_enabled
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'group_id', v_row.group_id,
    'version', v_row.version,
    'branding_enabled', v_row.branding_enabled,
    'brand_name', v_row.brand_name,
    'updated_at', v_row.updated_at
  );
END;
$$;

COMMENT ON FUNCTION public.fn_group_branding_set(UUID, JSONB) IS
  'Admin-only atomic upsert for portal_branding. Gates on admin_master membership or platform_role=admin. Raises 42501 otherwise. Calls the BEFORE UPDATE trigger on the update path to bump version + audit.';

REVOKE ALL ON FUNCTION public.fn_group_branding_set(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_group_branding_set(UUID, JSONB) TO authenticated, service_role;

-- ── 6. Self-test ─────────────────────────────────────────────────────────

DO $self_test$
DECLARE
  v_ok BOOLEAN;
BEGIN
  -- Hex colour validation.
  IF NOT public.fn_validate_hex_color('#2563eb') THEN
    RAISE EXCEPTION 'self-test: fn_validate_hex_color rejected valid value';
  END IF;
  IF NOT public.fn_validate_hex_color(NULL) THEN
    RAISE EXCEPTION 'self-test: fn_validate_hex_color rejected NULL (should accept)';
  END IF;
  IF public.fn_validate_hex_color('#bad') THEN
    RAISE EXCEPTION 'self-test: fn_validate_hex_color accepted short value';
  END IF;
  IF public.fn_validate_hex_color('red') THEN
    RAISE EXCEPTION 'self-test: fn_validate_hex_color accepted named colour';
  END IF;

  -- HTTPS URL validation.
  IF NOT public.fn_validate_https_url('https://cdn.example.com/logo.png', 500) THEN
    RAISE EXCEPTION 'self-test: fn_validate_https_url rejected valid https URL';
  END IF;
  IF public.fn_validate_https_url('http://cdn.example.com/logo.png', 500) THEN
    RAISE EXCEPTION 'self-test: fn_validate_https_url accepted http URL';
  END IF;
  IF public.fn_validate_https_url('javascript:alert(1)', 500) THEN
    RAISE EXCEPTION 'self-test: fn_validate_https_url accepted javascript: scheme';
  END IF;

  RAISE NOTICE 'L16-01 self-test OK';
END;
$self_test$;

COMMIT;
