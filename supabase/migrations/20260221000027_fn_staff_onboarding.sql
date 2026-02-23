-- ============================================================================
-- Omni Runner — RPCs for staff onboarding (create assessoria / join as professor)
-- Date: 2026-02-23
-- Sprint: 18.6.0
-- Origin: MICRO-PASSO 18.6.0 — Criar assessoria vs Entrar como professor
-- ============================================================================
-- SECURITY DEFINER: bypasses RLS so the functions can insert into
-- coaching_groups and coaching_members (which have no INSERT policy for users).
-- ============================================================================

BEGIN;

-- ── 1. fn_create_assessoria ────────────────────────────────────────────────
-- Creates a coaching group + admin_master membership + sets active group.
-- Only ASSESSORIA_STAFF users may call this.

CREATE OR REPLACE FUNCTION public.fn_create_assessoria(
  p_name TEXT,
  p_city TEXT DEFAULT ''
)
RETURNS JSONB AS $$
DECLARE
  v_uid          UUID;
  v_display_name TEXT;
  v_group_id     UUID;
  v_now_ms       BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_uid AND user_role = 'ASSESSORIA_STAFF'
  ) THEN
    RAISE EXCEPTION 'NOT_STAFF';
  END IF;

  IF length(trim(p_name)) < 3 OR length(trim(p_name)) > 80 THEN
    RAISE EXCEPTION 'INVALID_NAME';
  END IF;

  SELECT display_name INTO v_display_name
    FROM public.profiles WHERE id = v_uid;

  v_group_id := gen_random_uuid();
  v_now_ms   := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  INSERT INTO public.coaching_groups (id, name, coach_user_id, city)
  VALUES (v_group_id, trim(p_name), v_uid, COALESCE(trim(p_city), ''));

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_uid, v_group_id, COALESCE(v_display_name, 'Coach'), 'admin_master', v_now_ms);

  UPDATE public.profiles
    SET active_coaching_group_id = v_group_id, updated_at = now()
    WHERE id = v_uid;

  RETURN jsonb_build_object('status', 'created', 'group_id', v_group_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 2. fn_join_as_professor ────────────────────────────────────────────────
-- Joins an existing coaching group with role 'professor'.
-- Only ASSESSORIA_STAFF users may call this.

CREATE OR REPLACE FUNCTION public.fn_join_as_professor(p_group_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_uid          UUID;
  v_display_name TEXT;
  v_now_ms       BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_uid AND user_role = 'ASSESSORIA_STAFF'
  ) THEN
    RAISE EXCEPTION 'NOT_STAFF';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;

  SELECT display_name INTO v_display_name
    FROM public.profiles WHERE id = v_uid;

  v_now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_uid, p_group_id, COALESCE(v_display_name, 'Professor'), 'professor', v_now_ms)
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET role = 'professor', joined_at_ms = EXCLUDED.joined_at_ms;

  UPDATE public.profiles
    SET active_coaching_group_id = p_group_id, updated_at = now()
    WHERE id = v_uid;

  RETURN jsonb_build_object('status', 'joined', 'group_id', p_group_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
