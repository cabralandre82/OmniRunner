-- ============================================================================
-- Add watch_type to coaching_members for coach-managed device visibility
-- When NULL, auto-detect from coaching_device_links.
-- When set, coach's manual override takes precedence.
-- DECISAO 137
-- ============================================================================

BEGIN;

ALTER TABLE public.coaching_members
  ADD COLUMN IF NOT EXISTS watch_type text
    CHECK (watch_type IS NULL OR watch_type IN (
      'garmin', 'coros', 'suunto', 'apple_watch', 'polar', 'other'
    ));

COMMENT ON COLUMN public.coaching_members.watch_type IS
  'Coach-set device type. NULL = auto-detect from coaching_device_links.';

-- View that resolves watch_type: manual override > device link > null
CREATE OR REPLACE VIEW public.v_athlete_watch_type AS
SELECT
  cm.id AS member_id,
  cm.user_id,
  cm.group_id,
  cm.display_name,
  COALESCE(
    cm.watch_type,
    CASE dl.provider
      WHEN 'garmin' THEN 'garmin'
      WHEN 'apple'  THEN 'apple_watch'
      WHEN 'polar'  THEN 'polar'
      WHEN 'suunto' THEN 'suunto'
      ELSE NULL
    END
  ) AS resolved_watch_type,
  cm.watch_type IS NOT NULL AS is_manual_override,
  cm.watch_type AS manual_watch_type,
  dl.provider AS linked_provider
FROM public.coaching_members cm
LEFT JOIN LATERAL (
  SELECT provider
  FROM public.coaching_device_links d
  WHERE d.athlete_user_id = cm.user_id
    AND d.group_id = cm.group_id
  ORDER BY d.linked_at DESC
  LIMIT 1
) dl ON true
WHERE cm.role IN ('athlete', 'atleta');

-- RPC to update watch_type (coach-only)
CREATE OR REPLACE FUNCTION public.fn_set_athlete_watch_type(
  p_member_id uuid,
  p_watch_type text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid       uuid := auth.uid();
  v_group_id  uuid;
  v_caller    text;
BEGIN
  SELECT group_id INTO v_group_id
    FROM coaching_members WHERE id = p_member_id AND role IN ('athlete', 'atleta');

  IF v_group_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'MEMBER_NOT_FOUND');
  END IF;

  SELECT role INTO v_caller
    FROM coaching_members
    WHERE group_id = v_group_id AND user_id = v_uid;

  IF v_caller IS NULL OR v_caller NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_STAFF');
  END IF;

  UPDATE coaching_members
  SET watch_type = NULLIF(TRIM(p_watch_type), '')
  WHERE id = p_member_id;

  RETURN jsonb_build_object('ok', true);
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_set_athlete_watch_type(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_set_athlete_watch_type(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_set_athlete_watch_type(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_set_athlete_watch_type(uuid, text) TO service_role;

COMMIT;
