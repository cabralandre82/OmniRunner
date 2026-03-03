-- ============================================================================
-- Migration: Canonicalize coaching_members.role values
--
-- Taxonomy canônica (inglês, sem acentos):
--   admin_master  — dono da assessoria
--   coach         — professor/treinador (was 'professor')
--   assistant     — assistente (was 'assistente')
--   athlete       — atleta (was 'atleta')
--
-- Backfill order matters:
--   1. legacy 'coach' → 'admin_master' (coach was the old name for owner)
--   2. 'professor' → 'coach'
--   3. 'assistente' → 'assistant'
--   4. 'atleta' → 'athlete'
--
-- Idempotent: running 2x changes nothing.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 0. PRE-FLIGHT: audit existing coach rows (proof step)
-- ═══════════════════════════════════════════════════════════════════════════

-- Audit table — persists anomalies for post-migration review
CREATE TABLE IF NOT EXISTS public._role_migration_audit (
  id         SERIAL PRIMARY KEY,
  group_id   UUID NOT NULL,
  user_id    UUID NOT NULL,
  old_role   TEXT NOT NULL,
  resolution TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
DECLARE
  v_orphan_count INT;
  v_max_anomalies INT := 10;  -- stop condition: abort if more anomalies than this
BEGIN
  -- Record every coach-row that is NOT the group owner
  INSERT INTO public._role_migration_audit (group_id, user_id, old_role, resolution)
  SELECT cm.group_id, cm.user_id, 'coach', 'kept_as_coach_trainer'
  FROM public.coaching_members cm
  WHERE cm.role = 'coach'
    AND NOT EXISTS (
      SELECT 1 FROM public.coaching_groups cg
      WHERE cg.id = cm.group_id AND cg.coach_user_id = cm.user_id
    );

  GET DIAGNOSTICS v_orphan_count = ROW_COUNT;

  IF v_orphan_count > v_max_anomalies THEN
    RAISE EXCEPTION '[ROLE_MIGRATION] ABORTED — found % anomalous coach rows (threshold: %). Review _role_migration_audit and raise v_max_anomalies if safe.', v_orphan_count, v_max_anomalies;
  ELSIF v_orphan_count > 0 THEN
    RAISE WARNING '[ROLE_MIGRATION] Found % coach rows NOT matching coaching_groups.coach_user_id — logged to _role_migration_audit, mapped to "coach" (trainer)', v_orphan_count;
  ELSE
    RAISE NOTICE '[ROLE_MIGRATION] Pre-flight OK — all coach rows are verified group owners';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. BACKFILL coaching_members.role
-- ═══════════════════════════════════════════════════════════════════════════

-- 1a. Legacy 'coach' → 'admin_master' ONLY for verified group owners
--     Proof: baseline CHECK was ('coach','assistant','athlete'); coaching_groups.coach_user_id
--     is the owner FK; fn_create_assessoria originally inserted role='coach' for the creator.
UPDATE public.coaching_members cm
SET role = 'admin_master'
WHERE cm.role = 'coach'
  AND EXISTS (
    SELECT 1 FROM public.coaching_groups cg
    WHERE cg.id = cm.group_id AND cg.coach_user_id = cm.user_id
  );

-- 1a-safe. Any remaining 'coach' rows that are NOT the group owner stay as 'coach'
--          (they become the new "coach/trainer" role — no privilege escalation)
-- No UPDATE needed: they already have role='coach' which is the canonical trainer value.

-- 1b. 'professor' → 'coach'
UPDATE public.coaching_members SET role = 'coach' WHERE role = 'professor';

-- 1c. 'assistente' → 'assistant' (also handles legacy 'assistant' — no-op)
UPDATE public.coaching_members SET role = 'assistant' WHERE role = 'assistente';

-- 1d. 'atleta' → 'athlete' (also handles legacy 'athlete' — no-op)
UPDATE public.coaching_members SET role = 'athlete' WHERE role = 'atleta';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. UPDATE CHECK CONSTRAINT
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_members
  DROP CONSTRAINT IF EXISTS coaching_members_role_check;

ALTER TABLE public.coaching_members
  ADD CONSTRAINT coaching_members_role_check
  CHECK (role IN ('admin_master', 'coach', 'assistant', 'athlete'));

ALTER TABLE public.coaching_members
  ALTER COLUMN role SET DEFAULT 'athlete';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. BACKFILL coaching_join_requests.requested_role
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.coaching_join_requests SET requested_role = 'athlete' WHERE requested_role = 'atleta';
UPDATE public.coaching_join_requests SET requested_role = 'coach'   WHERE requested_role = 'professor';

ALTER TABLE public.coaching_join_requests
  DROP CONSTRAINT IF EXISTS coaching_join_requests_requested_role_check;

ALTER TABLE public.coaching_join_requests
  ADD CONSTRAINT coaching_join_requests_requested_role_check
  CHECK (requested_role IN ('athlete', 'coach'));

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. UPDATE RLS POLICIES — baseline (legacy 'coach','assistant')
-- ═══════════════════════════════════════════════════════════════════════════

-- 4a. baselines_read
DROP POLICY IF EXISTS "baselines_read" ON public.athlete_baselines;
CREATE POLICY "baselines_read" ON public.athlete_baselines FOR SELECT USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE coaching_members.group_id = athlete_baselines.group_id
      AND coaching_members.user_id = auth.uid()
      AND coaching_members.role IN ('admin_master', 'coach', 'assistant')
  )
);

-- 4b. coach_reads_insights
DROP POLICY IF EXISTS "coach_reads_insights" ON public.coach_insights;
CREATE POLICY "coach_reads_insights" ON public.coach_insights FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE coaching_members.group_id = coach_insights.group_id
      AND coaching_members.user_id = auth.uid()
      AND coaching_members.role IN ('admin_master', 'coach', 'assistant')
  )
);

-- 4c. coach_updates_insights
DROP POLICY IF EXISTS "coach_updates_insights" ON public.coach_insights;
CREATE POLICY "coach_updates_insights" ON public.coach_insights FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('admin_master', 'coach', 'assistant')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 4d. coaching_invites_read
DROP POLICY IF EXISTS "coaching_invites_read" ON public.coaching_invites;
CREATE POLICY "coaching_invites_read" ON public.coaching_invites FOR SELECT USING (
  auth.uid() = invited_user_id
  OR EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = coaching_invites.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach', 'assistant')
  )
);

-- 4e. trends_read
DROP POLICY IF EXISTS "trends_read" ON public.athlete_trends;
CREATE POLICY "trends_read" ON public.athlete_trends FOR SELECT USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE coaching_members.group_id = athlete_trends.group_id
      AND coaching_members.user_id = auth.uid()
      AND coaching_members.role IN ('admin_master', 'coach', 'assistant')
  )
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. UPDATE RLS POLICIES — custody/clearing/swap (were 'admin_master','professor')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "custody_own_group_read" ON public.custody_accounts;
CREATE POLICY "custody_own_group_read" ON public.custody_accounts FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = custody_accounts.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

DROP POLICY IF EXISTS "custody_deposits_own_read" ON public.custody_deposits;
CREATE POLICY "custody_deposits_own_read" ON public.custody_deposits FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = custody_deposits.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

DROP POLICY IF EXISTS "clearing_events_group_read" ON public.clearing_events;
CREATE POLICY "clearing_events_group_read" ON public.clearing_events FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id IN (
      SELECT DISTINCT (elem->>'issuer_group_id')::uuid
      FROM jsonb_array_elements(clearing_events.breakdown) elem
    )
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

DROP POLICY IF EXISTS "settlements_group_read" ON public.clearing_settlements;
CREATE POLICY "settlements_group_read" ON public.clearing_settlements FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE (cm.group_id = clearing_settlements.creditor_group_id
           OR cm.group_id = clearing_settlements.debtor_group_id)
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

DROP POLICY IF EXISTS "swap_orders_group_read" ON public.swap_orders;
CREATE POLICY "swap_orders_group_read" ON public.swap_orders FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE (cm.group_id = swap_orders.seller_group_id
           OR cm.group_id = swap_orders.buyer_group_id)
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. UPDATE RLS POLICIES — join requests (were 'admin_master','professor','assistente')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "join_requests_select_staff" ON public.coaching_join_requests;
CREATE POLICY "join_requests_select_staff" ON public.coaching_join_requests FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = coaching_join_requests.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach', 'assistant')
  )
);

DROP POLICY IF EXISTS "join_requests_update_staff" ON public.coaching_join_requests;
CREATE POLICY "join_requests_update_staff" ON public.coaching_join_requests FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = coaching_join_requests.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. UPDATE RLS POLICIES — championship templates (were 'admin_master','professor')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "championship_templates_insert" ON public.championship_templates;
CREATE POLICY "championship_templates_insert" ON public.championship_templates FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = championship_templates.owner_group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

DROP POLICY IF EXISTS "championship_templates_update" ON public.championship_templates;
CREATE POLICY "championship_templates_update" ON public.championship_templates FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = championship_templates.owner_group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

DROP POLICY IF EXISTS "championship_templates_delete" ON public.championship_templates;
CREATE POLICY "championship_templates_delete" ON public.championship_templates FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = championship_templates.owner_group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  )
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. UPDATE FUNCTIONS — staff_group_member_ids (RLS helper)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.staff_group_member_ids()
RETURNS SETOF UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT cm.user_id
  FROM public.coaching_members cm
  WHERE cm.group_id IN (
    SELECT cm2.group_id FROM public.coaching_members cm2
    WHERE cm2.user_id = auth.uid()
    AND cm2.role IN ('admin_master', 'coach', 'assistant')
  );
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. UPDATE FUNCTIONS — fn_create_assessoria
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_create_assessoria(p_name text, p_city text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
  v_uid          UUID;
  v_display_name TEXT;
  v_group_id     UUID;
  v_invite_code  TEXT;
  v_now_ms       BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_uid AND user_role = 'ASSESSORIA_STAFF'
  ) THEN RAISE EXCEPTION 'NOT_STAFF'; END IF;

  IF length(trim(p_name)) < 3 OR length(trim(p_name)) > 80 THEN
    RAISE EXCEPTION 'INVALID_NAME';
  END IF;

  SELECT display_name INTO v_display_name FROM public.profiles WHERE id = v_uid;

  v_group_id := gen_random_uuid();
  v_now_ms   := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  INSERT INTO public.coaching_groups (id, name, coach_user_id, city, created_at_ms)
  VALUES (v_group_id, trim(p_name), v_uid, COALESCE(trim(p_city), ''), v_now_ms)
  RETURNING invite_code INTO v_invite_code;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_uid, v_group_id, COALESCE(v_display_name, 'Coach'), 'admin_master', v_now_ms);

  UPDATE public.profiles
    SET active_coaching_group_id = v_group_id, updated_at = now()
    WHERE id = v_uid;

  RETURN jsonb_build_object(
    'status', 'created',
    'group_id', v_group_id,
    'invite_code', v_invite_code,
    'invite_link', 'https://omnirunner.app/invite/' || v_invite_code
  );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. UPDATE FUNCTIONS — fn_request_join
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_request_join(p_group_id UUID, p_role TEXT DEFAULT 'athlete')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid UUID; v_display TEXT; v_req_id UUID; v_role TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  v_role := COALESCE(p_role, 'athlete');
  IF v_role NOT IN ('athlete', 'coach') THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF EXISTS (SELECT 1 FROM public.coaching_members WHERE group_id = p_group_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'ALREADY_MEMBER';
  END IF;

  -- Cancel any existing pending request for same user+role
  UPDATE public.coaching_join_requests
    SET status = 'cancelled'
    WHERE group_id = p_group_id AND user_id = v_uid
      AND requested_role = v_role AND status = 'pending';

  SELECT display_name INTO v_display FROM public.profiles WHERE id = v_uid;
  v_req_id := gen_random_uuid();

  INSERT INTO public.coaching_join_requests (id, group_id, user_id, display_name, status, requested_role)
  VALUES (v_req_id, p_group_id, v_uid, COALESCE(v_display, ''), 'pending', v_role);

  RETURN jsonb_build_object('status', 'pending', 'request_id', v_req_id);
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11. UPDATE FUNCTIONS — fn_approve_join_request
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_approve_join_request(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid UUID; v_req RECORD; v_now_ms BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_req FROM public.coaching_join_requests WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_ALREADY_PROCESSED'; END IF;

  -- Coach requests need admin_master approval only
  IF v_req.requested_role = 'coach' THEN
    IF NOT EXISTS (SELECT 1 FROM public.coaching_members
      WHERE group_id = v_req.group_id AND user_id = v_uid AND role = 'admin_master') THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.coaching_members
      WHERE group_id = v_req.group_id AND user_id = v_uid AND role IN ('admin_master', 'coach')) THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  END IF;

  v_now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  -- Cancel other pending requests for same user+role
  UPDATE public.coaching_join_requests
    SET status = 'cancelled'
    WHERE group_id = v_req.group_id AND user_id = v_req.user_id
      AND requested_role = v_req.requested_role AND status = 'pending'
      AND id != p_request_id;

  UPDATE public.coaching_join_requests
    SET status = 'approved', reviewed_at = now(), reviewed_by = v_uid
    WHERE id = p_request_id;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_req.user_id, v_req.group_id, v_req.display_name, v_req.requested_role, v_now_ms)
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN jsonb_build_object('status', 'approved');
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 12. UPDATE FUNCTIONS — fn_reject_join_request
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_reject_join_request(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid UUID; v_req RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_req FROM public.coaching_join_requests WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_ALREADY_PROCESSED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.coaching_members
    WHERE group_id = v_req.group_id AND user_id = v_uid AND role IN ('admin_master', 'coach')) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  UPDATE public.coaching_join_requests SET status = 'rejected', reviewed_at = now(), reviewed_by = v_uid WHERE id = p_request_id;
  RETURN jsonb_build_object('status', 'rejected');
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 13. UPDATE FUNCTIONS — fn_remove_member
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_remove_member(p_target_user_id UUID, p_group_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid UUID; v_caller_role TEXT; v_target_role TEXT; v_target_name TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT role INTO v_caller_role FROM public.coaching_members WHERE group_id = p_group_id AND user_id = v_uid;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach', 'assistant') THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT role, display_name INTO v_target_role, v_target_name FROM public.coaching_members WHERE group_id = p_group_id AND user_id = p_target_user_id;
  IF v_target_role IS NULL THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;
  IF v_target_role = 'admin_master' THEN RAISE EXCEPTION 'CANNOT_REMOVE_ADMIN_MASTER'; END IF;
  IF v_caller_role = 'assistant' AND v_target_role IN ('coach', 'assistant') THEN RAISE EXCEPTION 'INSUFFICIENT_ROLE'; END IF;
  IF v_uid = p_target_user_id THEN RAISE EXCEPTION 'CANNOT_REMOVE_SELF'; END IF;

  DELETE FROM public.coaching_members WHERE group_id = p_group_id AND user_id = p_target_user_id;

  RETURN jsonb_build_object('status', 'removed', 'removed_name', COALESCE(v_target_name, ''));
END;
$fn$;

COMMIT;
