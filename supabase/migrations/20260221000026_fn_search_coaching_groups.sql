-- ============================================================================
-- Omni Runner — RPC fn_search_coaching_groups: search/lookup for onboarding
-- Date: 2026-02-23
-- Sprint: 18.5.0
-- Origin: MICRO-PASSO 18.5.0 — Escolher Assessoria
-- ============================================================================
-- SECURITY DEFINER: bypasses coaching_groups RLS so new users (not yet
-- members) can discover groups during onboarding.
--
-- Supports two modes:
--   1. p_query: ILIKE search by group name (min 2 chars)
--   2. p_group_ids: exact lookup by UUID array (for invite resolution)
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_search_coaching_groups(
  p_query     TEXT      DEFAULT '',
  p_group_ids UUID[]    DEFAULT ARRAY[]::UUID[]
)
RETURNS TABLE (
  id                 UUID,
  name               TEXT,
  logo_url           TEXT,
  city               TEXT,
  coach_display_name TEXT,
  member_count       BIGINT
) AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  IF array_length(p_group_ids, 1) > 0 THEN
    RETURN QUERY
      SELECT
        cg.id,
        cg.name,
        cg.logo_url,
        cg.city,
        COALESCE(p.display_name, 'Coach')  AS coach_display_name,
        (SELECT COUNT(*) FROM public.coaching_members cm
         WHERE cm.group_id = cg.id)::BIGINT AS member_count
      FROM public.coaching_groups cg
      LEFT JOIN public.profiles p ON p.id = cg.coach_user_id
      WHERE cg.id = ANY(p_group_ids)
      ORDER BY cg.name
      LIMIT 20;
  ELSIF length(trim(p_query)) >= 2 THEN
    RETURN QUERY
      SELECT
        cg.id,
        cg.name,
        cg.logo_url,
        cg.city,
        COALESCE(p.display_name, 'Coach')  AS coach_display_name,
        (SELECT COUNT(*) FROM public.coaching_members cm
         WHERE cm.group_id = cg.id)::BIGINT AS member_count
      FROM public.coaching_groups cg
      LEFT JOIN public.profiles p ON p.id = cg.coach_user_id
      WHERE cg.name ILIKE '%' || trim(p_query) || '%'
      ORDER BY cg.name
      LIMIT 20;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
