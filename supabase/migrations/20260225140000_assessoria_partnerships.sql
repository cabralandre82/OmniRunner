-- ============================================================================
-- Omni Runner — Assessoria Partnerships + Championship join requests
-- Date: 2026-02-25
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. assessoria_partnerships — bilateral links between coaching groups
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.assessoria_partnerships (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id_a      UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  group_id_b      UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected')),
  requested_by    UUID NOT NULL REFERENCES auth.users(id),
  accepted_by     UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at    TIMESTAMPTZ,
  CONSTRAINT partnerships_no_self CHECK (group_id_a <> group_id_b),
  CONSTRAINT partnerships_unique UNIQUE (group_id_a, group_id_b)
);

CREATE INDEX idx_partnerships_group_a ON public.assessoria_partnerships(group_id_a, status);
CREATE INDEX idx_partnerships_group_b ON public.assessoria_partnerships(group_id_b, status);

ALTER TABLE public.assessoria_partnerships ENABLE ROW LEVEL SECURITY;

CREATE POLICY partnerships_select ON public.assessoria_partnerships
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
        AND (cm.group_id = group_id_a OR cm.group_id = group_id_b)
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Add origin column to championship_invites for join requests
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.championship_invites
  ADD COLUMN IF NOT EXISTS origin TEXT NOT NULL DEFAULT 'invited'
    CHECK (origin IN ('invited', 'requested'));

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RPC: fn_list_partnerships — list partnerships for a group
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_list_partnerships(p_group_id UUID)
RETURNS TABLE (
  partnership_id UUID,
  partner_group_id UUID,
  partner_name TEXT,
  partner_athlete_count BIGINT,
  status TEXT,
  is_requester BOOLEAN,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER AS $fn$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS partnership_id,
    CASE WHEN p.group_id_a = p_group_id THEN p.group_id_b ELSE p.group_id_a END AS partner_group_id,
    cg.name AS partner_name,
    (SELECT count(*) FROM public.coaching_members cm2
     WHERE cm2.group_id = CASE WHEN p.group_id_a = p_group_id THEN p.group_id_b ELSE p.group_id_a END
       AND cm2.role = 'athlete') AS partner_athlete_count,
    p.status,
    (p.group_id_a = p_group_id) AS is_requester,
    p.created_at
  FROM public.assessoria_partnerships p
  JOIN public.coaching_groups cg
    ON cg.id = CASE WHEN p.group_id_a = p_group_id THEN p.group_id_b ELSE p.group_id_a END
  WHERE p.group_id_a = p_group_id OR p.group_id_b = p_group_id
  ORDER BY
    CASE p.status WHEN 'pending' THEN 0 WHEN 'accepted' THEN 1 ELSE 2 END,
    p.created_at DESC;
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPC: fn_partner_championships — open champs from partner assessorias
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
LANGUAGE plpgsql SECURITY DEFINER AS $fn$
BEGIN
  RETURN QUERY
  WITH partner_groups AS (
    SELECT CASE WHEN p.group_id_a = p_group_id THEN p.group_id_b ELSE p.group_id_a END AS gid
    FROM public.assessoria_partnerships p
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
    (SELECT count(*) FROM public.championship_participants cp WHERE cp.championship_id = c.id) AS participant_count,
    EXISTS (
      SELECT 1 FROM public.championship_invites ci
      WHERE ci.championship_id = c.id AND ci.to_group_id = p_group_id
    ) AS already_invited
  FROM public.championships c
  JOIN partner_groups pg ON pg.gid = c.host_group_id
  JOIN public.coaching_groups cg ON cg.id = c.host_group_id
  WHERE c.status IN ('open', 'active')
    AND c.host_group_id <> p_group_id
  ORDER BY c.start_at ASC;
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. RPC: fn_request_partnership — send partnership request
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_request_partnership(
  p_my_group_id UUID,
  p_target_group_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $fn$
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
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_my_group_id AND user_id = v_uid AND role = 'admin_master'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN_MASTER';
  END IF;

  -- Check existing (either direction)
  SELECT * INTO v_existing FROM public.assessoria_partnerships
  WHERE (group_id_a = p_my_group_id AND group_id_b = p_target_group_id)
     OR (group_id_a = p_target_group_id AND group_id_b = p_my_group_id);

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'accepted' THEN RETURN 'already_partners'; END IF;
    IF v_existing.status = 'pending' THEN RETURN 'already_pending'; END IF;
    IF v_existing.status = 'rejected' THEN
      UPDATE public.assessoria_partnerships
      SET status = 'pending', requested_by = v_uid, responded_at = NULL, accepted_by = NULL, created_at = now()
      WHERE id = v_existing.id;
      RETURN 'requested';
    END IF;
  END IF;

  INSERT INTO public.assessoria_partnerships (group_id_a, group_id_b, requested_by)
  VALUES (p_my_group_id, p_target_group_id, v_uid);

  RETURN 'requested';
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. RPC: fn_respond_partnership — accept or reject
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_respond_partnership(
  p_partnership_id UUID,
  p_accept BOOLEAN
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID;
  v_partnership RECORD;
  v_my_group UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_partnership FROM public.assessoria_partnerships WHERE id = p_partnership_id;
  IF v_partnership IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF v_partnership.status <> 'pending' THEN RETURN 'already_responded'; END IF;

  -- The responder must be admin_master of group_b (the invited side)
  v_my_group := v_partnership.group_id_b;
  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_my_group AND user_id = v_uid AND role = 'admin_master'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN_MASTER';
  END IF;

  UPDATE public.assessoria_partnerships
  SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END,
      accepted_by = v_uid,
      responded_at = now()
  WHERE id = p_partnership_id;

  RETURN CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END;
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. RPC: fn_request_champ_join — assessoria requests to join a championship
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_request_champ_join(
  p_championship_id UUID,
  p_group_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID;
  v_champ RECORD;
  v_existing RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = v_uid AND role IN ('admin_master', 'professor')
  ) THEN
    RAISE EXCEPTION 'NOT_STAFF';
  END IF;

  SELECT * INTO v_champ FROM public.championships WHERE id = p_championship_id;
  IF v_champ IS NULL THEN RAISE EXCEPTION 'CHAMP_NOT_FOUND'; END IF;
  IF v_champ.status NOT IN ('open', 'active') THEN RAISE EXCEPTION 'CHAMP_NOT_OPEN'; END IF;

  -- Must be partner of host
  IF NOT EXISTS (
    SELECT 1 FROM public.assessoria_partnerships
    WHERE status = 'accepted'
      AND ((group_id_a = p_group_id AND group_id_b = v_champ.host_group_id)
        OR (group_id_a = v_champ.host_group_id AND group_id_b = p_group_id))
  ) THEN
    RAISE EXCEPTION 'NOT_PARTNER';
  END IF;

  -- Check existing invite
  SELECT * INTO v_existing FROM public.championship_invites
  WHERE championship_id = p_championship_id AND to_group_id = p_group_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'accepted' THEN RETURN 'already_accepted'; END IF;
    IF v_existing.status = 'pending' THEN RETURN 'already_pending'; END IF;
    IF v_existing.status IN ('declined', 'revoked') THEN
      UPDATE public.championship_invites
      SET status = 'pending', origin = 'requested', invited_by = v_uid,
          responded_by = NULL, responded_at = NULL
      WHERE id = v_existing.id;
      RETURN 'requested';
    END IF;
  END IF;

  INSERT INTO public.championship_invites (championship_id, to_group_id, invited_by, origin)
  VALUES (p_championship_id, p_group_id, v_uid, 'requested');

  RETURN 'requested';
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. RPC: fn_search_assessorias — search groups by name for partnership
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
LANGUAGE plpgsql SECURITY DEFINER AS $fn$
BEGIN
  RETURN QUERY
  SELECT
    cg.id AS group_id,
    cg.name AS group_name,
    (SELECT count(*) FROM public.coaching_members cm
     WHERE cm.group_id = cg.id AND cm.role = 'athlete') AS athlete_count
  FROM public.coaching_groups cg
  WHERE cg.name ILIKE '%' || p_query || '%'
    AND (p_exclude_group_id IS NULL OR cg.id <> p_exclude_group_id)
  ORDER BY cg.name
  LIMIT 20;
END;
$fn$;

COMMIT;
