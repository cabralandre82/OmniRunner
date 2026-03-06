-- ============================================================================
-- Partner Assessorias: RLS, role fixes, auth, scalability
-- Date: 2026-03-18
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix SELECT policy — old roles (professor/assistente) → (coach/assistant)
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "partnerships_select" ON public.assessoria_partnerships;
CREATE POLICY "partnerships_select" ON public.assessoria_partnerships
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
        AND (cm.group_id = group_id_a OR cm.group_id = group_id_b)
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. INSERT, UPDATE, DELETE policies
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "partnerships_insert" ON public.assessoria_partnerships;
CREATE POLICY "partnerships_insert" ON public.assessoria_partnerships
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
        AND cm.group_id = group_id_a
    )
  );

DROP POLICY IF EXISTS "partnerships_update" ON public.assessoria_partnerships;
CREATE POLICY "partnerships_update" ON public.assessoria_partnerships
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
        AND cm.group_id = group_id_b
    )
  );

DROP POLICY IF EXISTS "partnerships_delete" ON public.assessoria_partnerships;
CREATE POLICY "partnerships_delete" ON public.assessoria_partnerships
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
        AND (cm.group_id = group_id_a OR cm.group_id = group_id_b)
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Trigram index for fn_search_assessorias (ILIKE '%query%')
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_coaching_groups_name_trgm
  ON public.coaching_groups USING gin (name gin_trgm_ops);

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. fn_count_pending_partnerships — lightweight count for dashboard badge
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_count_pending_partnerships(p_group_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID;
  v_cnt INTEGER;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = p_group_id AND user_id = v_uid
      AND role IN ('admin_master', 'coach', 'assistant')
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT count(*)::int INTO v_cnt
  FROM assessoria_partnerships
  WHERE status = 'pending'
    AND group_id_b = p_group_id;

  RETURN v_cnt;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Rewrite fn_list_partnerships — auth check, no N+1, pagination
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_list_partnerships(
  p_group_id UUID,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  partnership_id UUID,
  partner_group_id UUID,
  partner_name TEXT,
  partner_athlete_count BIGINT,
  status TEXT,
  is_requester BOOLEAN,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = p_group_id AND user_id = v_uid
      AND role IN ('admin_master', 'coach', 'assistant')
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS partnership_id,
    CASE WHEN p.group_id_a = p_group_id THEN p.group_id_b ELSE p.group_id_a END AS partner_group_id,
    cg.name AS partner_name,
    COALESCE(ac.cnt, 0) AS partner_athlete_count,
    p.status,
    (p.group_id_a = p_group_id) AS is_requester,
    p.created_at
  FROM assessoria_partnerships p
  JOIN coaching_groups cg
    ON cg.id = CASE WHEN p.group_id_a = p_group_id THEN p.group_id_b ELSE p.group_id_a END
  LEFT JOIN LATERAL (
    SELECT count(*) AS cnt
    FROM coaching_members cm2
    WHERE cm2.group_id = cg.id AND cm2.role = 'athlete'
  ) ac ON true
  WHERE p.group_id_a = p_group_id OR p.group_id_b = p_group_id
  ORDER BY
    CASE p.status WHEN 'pending' THEN 0 WHEN 'accepted' THEN 1 ELSE 2 END,
    p.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Fix fn_request_partnership — auth check, handle unique_violation
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_request_partnership(
  p_my_group_id UUID,
  p_target_group_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID;
  v_existing RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF p_my_group_id = p_target_group_id THEN
    RAISE EXCEPTION 'CANNOT_PARTNER_SELF';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = p_my_group_id AND user_id = v_uid AND role = 'admin_master'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN_MASTER';
  END IF;

  SELECT * INTO v_existing FROM assessoria_partnerships
  WHERE (group_id_a = p_my_group_id AND group_id_b = p_target_group_id)
     OR (group_id_a = p_target_group_id AND group_id_b = p_my_group_id);

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'accepted' THEN RETURN 'already_partners'; END IF;
    IF v_existing.status = 'pending' THEN RETURN 'already_pending'; END IF;
    IF v_existing.status = 'rejected' THEN
      UPDATE assessoria_partnerships
      SET status = 'pending', requested_by = v_uid,
          responded_at = NULL, accepted_by = NULL, created_at = now()
      WHERE id = v_existing.id;
      RETURN 'requested';
    END IF;
  END IF;

  BEGIN
    INSERT INTO assessoria_partnerships (group_id_a, group_id_b, requested_by)
    VALUES (p_my_group_id, p_target_group_id, v_uid);
  EXCEPTION WHEN unique_violation THEN
    RETURN 'already_pending';
  END;

  RETURN 'requested';
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Fix fn_respond_partnership — set search_path
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_respond_partnership(
  p_partnership_id UUID,
  p_accept BOOLEAN
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID;
  v_partnership RECORD;
  v_my_group UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_partnership FROM assessoria_partnerships WHERE id = p_partnership_id;
  IF v_partnership IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF v_partnership.status <> 'pending' THEN RETURN 'already_responded'; END IF;

  v_my_group := v_partnership.group_id_b;
  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = v_my_group AND user_id = v_uid AND role = 'admin_master'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN_MASTER';
  END IF;

  UPDATE assessoria_partnerships
  SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END,
      accepted_by = v_uid,
      responded_at = now()
  WHERE id = p_partnership_id;

  RETURN CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. Fix fn_search_assessorias — set search_path
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_search_assessorias(
  p_query TEXT,
  p_exclude_group_id UUID DEFAULT NULL
)
RETURNS TABLE (
  group_id UUID,
  group_name TEXT,
  athlete_count BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  RETURN QUERY
  SELECT
    cg.id AS group_id,
    cg.name AS group_name,
    (SELECT count(*) FROM coaching_members cm
     WHERE cm.group_id = cg.id AND cm.role = 'athlete') AS athlete_count
  FROM coaching_groups cg
  WHERE cg.name ILIKE '%' || p_query || '%'
    AND (p_exclude_group_id IS NULL OR cg.id <> p_exclude_group_id)
  ORDER BY cg.name
  LIMIT 20;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. Fix fn_request_champ_join — professor → coach
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_request_champ_join(
  p_championship_id UUID,
  p_group_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID;
  v_champ RECORD;
  v_existing RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = p_group_id AND user_id = v_uid AND role IN ('admin_master', 'coach')
  ) THEN
    RAISE EXCEPTION 'NOT_STAFF';
  END IF;

  SELECT * INTO v_champ FROM championships WHERE id = p_championship_id;
  IF v_champ IS NULL THEN RAISE EXCEPTION 'CHAMP_NOT_FOUND'; END IF;
  IF v_champ.status NOT IN ('open', 'active') THEN RAISE EXCEPTION 'CHAMP_NOT_OPEN'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM assessoria_partnerships
    WHERE status = 'accepted'
      AND ((group_id_a = p_group_id AND group_id_b = v_champ.host_group_id)
        OR (group_id_a = v_champ.host_group_id AND group_id_b = p_group_id))
  ) THEN
    RAISE EXCEPTION 'NOT_PARTNER';
  END IF;

  SELECT * INTO v_existing FROM championship_invites
  WHERE championship_id = p_championship_id AND to_group_id = p_group_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'accepted' THEN RETURN 'already_accepted'; END IF;
    IF v_existing.status = 'pending' THEN RETURN 'already_pending'; END IF;
    IF v_existing.status IN ('declined', 'revoked') THEN
      UPDATE championship_invites
      SET status = 'pending', origin = 'requested', invited_by = v_uid,
          responded_by = NULL, responded_at = NULL
      WHERE id = v_existing.id;
      RETURN 'requested';
    END IF;
  END IF;

  INSERT INTO championship_invites (championship_id, to_group_id, invited_by, origin)
  VALUES (p_championship_id, p_group_id, v_uid, 'requested');

  RETURN 'requested';
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. Fix fn_partner_championships — set search_path + auth
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_partner_championships(p_group_id UUID)
RETURNS TABLE (
  championship_id UUID,
  championship_name TEXT,
  host_group_id UUID,
  host_group_name TEXT,
  metric TEXT,
  start_at TIMESTAMPTZ,
  end_at TIMESTAMPTZ,
  status TEXT,
  max_participants INT,
  participant_count BIGINT,
  already_invited BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = p_group_id AND user_id = auth.uid()
      AND role IN ('admin_master', 'coach', 'assistant')
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  WITH partner_groups AS (
    SELECT CASE WHEN p.group_id_a = p_group_id THEN p.group_id_b ELSE p.group_id_a END AS gid
    FROM assessoria_partnerships p
    WHERE p.status = 'accepted'
      AND (p.group_id_a = p_group_id OR p.group_id_b = p_group_id)
  )
  SELECT
    c.id AS championship_id,
    c.name AS championship_name,
    c.host_group_id,
    cg.name AS host_group_name,
    c.metric,
    c.start_at,
    c.end_at,
    c.status,
    c.max_participants,
    (SELECT count(*) FROM championship_participants cp WHERE cp.championship_id = c.id) AS participant_count,
    EXISTS (
      SELECT 1 FROM championship_invites ci
      WHERE ci.championship_id = c.id AND ci.to_group_id = p_group_id
    ) AS already_invited
  FROM championships c
  JOIN partner_groups pg ON pg.gid = c.host_group_id
  JOIN coaching_groups cg ON cg.id = c.host_group_id
  WHERE c.status IN ('open', 'active')
    AND c.host_group_id <> p_group_id
  ORDER BY c.start_at ASC;
END;
$$;

COMMIT;
