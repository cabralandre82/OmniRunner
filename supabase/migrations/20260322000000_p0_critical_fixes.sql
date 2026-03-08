-- P0 Critical Fixes Migration
-- 1. Add total_elevation_m column to sessions table
-- 2. Enable RLS on coin_ledger_archive
-- 3. Add search_path to fn_remove_member and fn_join_as_professor

-- ══════════════════════════════════════════════════════════════════
-- 1. Add total_elevation_m to sessions (needed for championship elevation metric)
-- ══════════════════════════════════════════════════════════════════
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS total_elevation_m DOUBLE PRECISION NOT NULL DEFAULT 0;

-- ══════════════════════════════════════════════════════════════════
-- 2. Enable RLS on coin_ledger_archive (financial data must be protected)
-- ══════════════════════════════════════════════════════════════════
ALTER TABLE public.coin_ledger_archive ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_read_ledger_archive" ON public.coin_ledger_archive
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

CREATE POLICY "user_read_own_ledger_archive" ON public.coin_ledger_archive
  FOR SELECT USING (user_id = auth.uid());

-- ══════════════════════════════════════════════════════════════════
-- 3. Fix fn_remove_member: add SET search_path
-- ══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_remove_member(UUID, UUID);
CREATE FUNCTION public.fn_remove_member(p_group_id UUID, p_target_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid UUID; v_caller_role TEXT; v_target_role TEXT;
BEGIN
  v_uid := auth.uid();
  SELECT role INTO v_caller_role FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = v_uid;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('error', 'FORBIDDEN');
  END IF;
  SELECT role INTO v_target_role FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = p_target_user_id;
  IF v_target_role IS NULL THEN
    RETURN jsonb_build_object('error', 'NOT_MEMBER');
  END IF;
  IF v_target_role = 'admin_master' THEN
    RETURN jsonb_build_object('error', 'CANNOT_REMOVE_ADMIN');
  END IF;
  IF v_caller_role = 'coach' AND v_target_role = 'coach' THEN
    RETURN jsonb_build_object('error', 'CANNOT_REMOVE_PEER');
  END IF;
  DELETE FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = p_target_user_id;
  UPDATE public.profiles
    SET active_coaching_group_id = NULL, updated_at = now()
    WHERE id = p_target_user_id AND active_coaching_group_id = p_group_id;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- ══════════════════════════════════════════════════════════════════
-- 4. Fix fn_join_as_professor: add SET search_path
-- ══════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_join_as_professor') THEN
  DROP FUNCTION public.fn_join_as_professor(UUID);
  CREATE FUNCTION public.fn_join_as_professor(p_group_id UUID)
  RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $f$
  DECLARE
    v_uid UUID; v_display_name TEXT; v_now_ms BIGINT;
  BEGIN
    v_uid := auth.uid();
    v_now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
    SELECT display_name INTO v_display_name FROM public.profiles WHERE id = v_uid;
    INSERT INTO public.coaching_members (group_id, user_id, role, display_name, joined_at_ms, updated_at)
    VALUES (p_group_id, v_uid, 'coach', COALESCE(v_display_name, ''), v_now_ms, now())
    ON CONFLICT (group_id, user_id) DO UPDATE SET role = 'coach', updated_at = now();
    RETURN jsonb_build_object('ok', true);
  END;
  $f$;
END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 5. Backfill issuer_group_id for existing ISSUE ledger entries
-- ══════════════════════════════════════════════════════════════════
DO $$
BEGIN
  UPDATE public.coin_ledger
  SET issuer_group_id = ti.group_id
  FROM public.token_intents ti
  WHERE coin_ledger.ref_id = ti.id::text
    AND coin_ledger.reason = 'institution_token_issue'
    AND coin_ledger.issuer_group_id IS NULL
    AND ti.group_id IS NOT NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Backfill skipped: %', SQLERRM;
END $$;
