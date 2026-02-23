-- ============================================================================
-- Omni Runner — Profile onboarding state columns
-- Date: 2026-02-22
-- Sprint: 18.1.2
-- ============================================================================
-- Adds three columns to profiles for onboarding flow tracking:
--   onboarding_state : tracks where the user is in the onboarding funnel
--   user_role        : self-declared role (atleta vs assessoria staff)
--   created_via      : auth provider that created the account
--
-- Defaults are chosen so existing rows remain valid without data backfill.
-- The handle_new_user trigger is updated to auto-detect created_via from
-- auth.users metadata.
-- ============================================================================

BEGIN;

-- ── 1. New columns ──────────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS onboarding_state TEXT NOT NULL DEFAULT 'NEW',
  ADD COLUMN IF NOT EXISTS user_role        TEXT,
  ADD COLUMN IF NOT EXISTS created_via      TEXT NOT NULL DEFAULT 'OTHER';

-- ── 2. CHECK constraints ────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD CONSTRAINT chk_onboarding_state
    CHECK (onboarding_state IN ('NEW', 'ROLE_SELECTED', 'READY'));

ALTER TABLE public.profiles
  ADD CONSTRAINT chk_user_role
    CHECK (user_role IS NULL OR user_role IN ('ATLETA', 'ASSESSORIA_STAFF'));

ALTER TABLE public.profiles
  ADD CONSTRAINT chk_created_via
    CHECK (created_via IN ('ANON', 'EMAIL', 'OAUTH_GOOGLE', 'OAUTH_APPLE', 'OTHER'));

-- ── 3. Update trigger to populate created_via on signup ─────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  _provider TEXT;
  _via      TEXT;
BEGIN
  _provider := COALESCE(
    NEW.raw_app_meta_data->>'provider',
    ''
  );

  CASE _provider
    WHEN 'google' THEN _via := 'OAUTH_GOOGLE';
    WHEN 'apple'  THEN _via := 'OAUTH_APPLE';
    WHEN 'email'  THEN _via := 'EMAIL';
    ELSE
      IF NEW.is_anonymous THEN
        _via := 'ANON';
      ELSE
        _via := 'OTHER';
      END IF;
  END CASE;

  INSERT INTO public.profiles (id, display_name, avatar_url, created_via)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'Runner'),
    NEW.raw_user_meta_data->>'avatar_url',
    _via
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
