-- Fix remaining RLS policies that still reference Portuguese role names
-- ('professor', 'assistente') instead of English ('coach', 'assistant').
-- Previous fix (20260303300000) corrected some but missed these tables.

-- ══════════════════════════════════════════════════════════════════════════
-- 1. support_tickets (5 policies)
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "staff_read_own_tickets" ON public.support_tickets;
CREATE POLICY "staff_read_own_tickets" ON public.support_tickets FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = support_tickets.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach', 'assistant')
  )
);

DROP POLICY IF EXISTS "staff_insert_tickets" ON public.support_tickets;
CREATE POLICY "staff_insert_tickets" ON public.support_tickets FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = support_tickets.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach', 'assistant')
  )
);

DROP POLICY IF EXISTS "staff_update_own_tickets" ON public.support_tickets;
CREATE POLICY "staff_update_own_tickets" ON public.support_tickets FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = support_tickets.group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach', 'assistant')
  )
);

-- support_messages
DROP POLICY IF EXISTS "staff_read_own_messages" ON public.support_messages;
CREATE POLICY "staff_read_own_messages" ON public.support_messages FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.support_tickets t
    JOIN public.coaching_members cm ON cm.group_id = t.group_id
    WHERE t.id = support_messages.ticket_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach', 'assistant')
  )
);

DROP POLICY IF EXISTS "staff_insert_messages" ON public.support_messages;
CREATE POLICY "staff_insert_messages" ON public.support_messages FOR INSERT WITH CHECK (
  sender_role = 'staff'
  AND sender_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.support_tickets t
    JOIN public.coaching_members cm ON cm.group_id = t.group_id
    WHERE t.id = support_messages.ticket_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach', 'assistant')
  )
);

-- ══════════════════════════════════════════════════════════════════════════
-- 2. clearing_cases, clearing_case_items, clearing_case_events
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clearing_cases') THEN

  EXECUTE 'DROP POLICY IF EXISTS "clearing_cases_select" ON public.clearing_cases';
  EXECUTE $p$CREATE POLICY "clearing_cases_select" ON public.clearing_cases FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
        AND (cm.group_id = clearing_cases.from_group_id OR cm.group_id = clearing_cases.to_group_id)
    )
  )$p$;

  EXECUTE 'DROP POLICY IF EXISTS "clearing_case_items_select" ON public.clearing_case_items';
  EXECUTE $p$CREATE POLICY "clearing_case_items_select" ON public.clearing_case_items FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.clearing_cases cc
      JOIN public.coaching_members cm ON cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
        AND (cm.group_id = cc.from_group_id OR cm.group_id = cc.to_group_id)
      WHERE cc.id = clearing_case_items.case_id
    )
  )$p$;

  EXECUTE 'DROP POLICY IF EXISTS "clearing_case_events_select" ON public.clearing_case_events';
  EXECUTE $p$CREATE POLICY "clearing_case_events_select" ON public.clearing_case_events FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.clearing_cases cc
      JOIN public.coaching_members cm ON cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
        AND (cm.group_id = cc.from_group_id OR cm.group_id = cc.to_group_id)
      WHERE cc.id = clearing_case_events.case_id
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 3. coaching_token_inventory & token_intents
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'coaching_token_inventory') THEN

  EXECUTE 'DROP POLICY IF EXISTS "token_inventory_staff_read" ON public.coaching_token_inventory';
  EXECUTE $p$CREATE POLICY "token_inventory_staff_read" ON public.coaching_token_inventory FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_token_inventory.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  )$p$;

END IF;

IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'token_intents') THEN

  EXECUTE 'DROP POLICY IF EXISTS "token_intents_staff_read" ON public.token_intents';
  EXECUTE $p$CREATE POLICY "token_intents_staff_read" ON public.token_intents FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = token_intents.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 4. coaching_badge_inventory
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'coaching_badge_inventory') THEN

  EXECUTE 'DROP POLICY IF EXISTS "badge_inventory_staff_read" ON public.coaching_badge_inventory';
  EXECUTE $p$CREATE POLICY "badge_inventory_staff_read" ON public.coaching_badge_inventory FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_badge_inventory.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 5. portal_audit_log
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'portal_audit_log') THEN

  EXECUTE 'DROP POLICY IF EXISTS "audit_platform_read" ON public.portal_audit_log';
  EXECUTE $p$CREATE POLICY "audit_platform_read" ON public.portal_audit_log FOR SELECT USING (
    group_id IN (
      SELECT group_id FROM public.coaching_members
      WHERE user_id = auth.uid() AND role IN ('admin_master', 'coach')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 6. league_enrollments
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'league_enrollments') THEN

  EXECUTE 'DROP POLICY IF EXISTS "league_enrollments_staff_insert" ON public.league_enrollments';
  EXECUTE $p$CREATE POLICY "league_enrollments_staff_insert" ON public.league_enrollments FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = league_enrollments.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 7. weekly_goals
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'weekly_goals') THEN

  EXECUTE 'DROP POLICY IF EXISTS "wg_staff_read" ON public.weekly_goals';
  EXECUTE $p$CREATE POLICY "wg_staff_read" ON public.weekly_goals FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
        AND cm.group_id IN (
          SELECT cm2.group_id FROM public.coaching_members cm2
          WHERE cm2.user_id = weekly_goals.user_id AND cm2.role = 'athlete'
        )
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 8. championship tables (missed by previous fix)
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'championship_templates') THEN

  EXECUTE 'DROP POLICY IF EXISTS "championship_templates_select" ON public.championship_templates';
  EXECUTE $p$CREATE POLICY "championship_templates_select" ON public.championship_templates FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = championship_templates.owner_group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  )$p$;

END IF;

IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'championships') THEN

  EXECUTE 'DROP POLICY IF EXISTS "championships_select" ON public.championships';
  EXECUTE $p$CREATE POLICY "championships_select" ON public.championships FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = championships.host_group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  )$p$;

END IF;

IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'championship_invites') THEN

  EXECUTE 'DROP POLICY IF EXISTS "championship_invites_select" ON public.championship_invites';
  EXECUTE $p$CREATE POLICY "championship_invites_select" ON public.championship_invites FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
        AND (
          cm.group_id = championship_invites.to_group_id
          OR cm.group_id = (
            SELECT c.host_group_id FROM public.championships c
            WHERE c.id = championship_invites.championship_id
          )
        )
    )
  )$p$;

END IF;

IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'championship_badges') THEN

  EXECUTE 'DROP POLICY IF EXISTS "championship_badges_staff" ON public.championship_badges';
  EXECUTE $p$CREATE POLICY "championship_badges_staff" ON public.championship_badges FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.championships c
      JOIN public.coaching_members cm ON cm.group_id = c.host_group_id
      WHERE c.id = championship_badges.championship_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 9. billing_limits
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'billing_limits') THEN

  EXECUTE 'DROP POLICY IF EXISTS "billing_limits_staff_read" ON public.billing_limits';
  EXECUTE $p$CREATE POLICY "billing_limits_staff_read" ON public.billing_limits FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_limits.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 10. billing_products (global catalog — no group_id, just check staff role)
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'billing_products') THEN

  EXECUTE 'DROP POLICY IF EXISTS "billing_products_staff_read" ON public.billing_products';
  EXECUTE $p$CREATE POLICY "billing_products_staff_read" ON public.billing_products FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 11. product_events (staff reads athlete events via group join)
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'product_events') THEN

  EXECUTE 'DROP POLICY IF EXISTS "product_events_staff_read" ON public.product_events';
  EXECUTE $p$CREATE POLICY "product_events_staff_read" ON public.product_events FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      JOIN public.coaching_members target_cm
        ON target_cm.group_id = cm.group_id
        AND target_cm.user_id = product_events.user_id
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  )$p$;

END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 12. fn_remove_member (uses 'assistente' in role check)
-- ══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_remove_member(UUID, UUID);
CREATE FUNCTION public.fn_remove_member(p_group_id UUID, p_target_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_caller_role TEXT; v_target_role TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT role INTO v_caller_role FROM public.coaching_members WHERE group_id = p_group_id AND user_id = v_uid;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach', 'assistant') THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT role INTO v_target_role FROM public.coaching_members WHERE group_id = p_group_id AND user_id = p_target_user_id;
  IF v_target_role IS NULL THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;
  IF v_target_role = 'admin_master' THEN RAISE EXCEPTION 'CANNOT_REMOVE_ADMIN_MASTER'; END IF;
  IF v_caller_role = 'assistant' AND v_target_role IN ('coach', 'assistant') THEN RAISE EXCEPTION 'INSUFFICIENT_ROLE'; END IF;
  IF v_uid = p_target_user_id THEN RAISE EXCEPTION 'CANNOT_REMOVE_SELF'; END IF;

  DELETE FROM public.coaching_members WHERE group_id = p_group_id AND user_id = p_target_user_id;

  UPDATE public.profiles
    SET active_coaching_group_id = NULL, updated_at = now()
    WHERE id = p_target_user_id AND active_coaching_group_id = p_group_id;

  RETURN jsonb_build_object('status', 'removed', 'user_id', p_target_user_id);
END; $fn$;

-- ══════════════════════════════════════════════════════════════════════════
-- 13. fn_join_as_professor → fix to use 'coach' role
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_join_as_professor') THEN
  EXECUTE $fn$
    CREATE OR REPLACE FUNCTION public.fn_join_as_professor(p_group_id UUID)
    RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $f$
    DECLARE
      v_uid UUID; v_display_name TEXT; v_now_ms BIGINT;
    BEGIN
      v_uid := auth.uid();
      IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

      IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_group_id) THEN
        RAISE EXCEPTION 'GROUP_NOT_FOUND';
      END IF;

      SELECT display_name INTO v_display_name FROM public.profiles WHERE id = v_uid;
      v_now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

      INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
      VALUES (v_uid, p_group_id, COALESCE(v_display_name, 'Professor'), 'coach', v_now_ms)
      ON CONFLICT (group_id, user_id)
      DO UPDATE SET role = 'coach', joined_at_ms = EXCLUDED.joined_at_ms;

      RETURN jsonb_build_object('status', 'joined', 'role', 'coach');
    END; $f$;
  $fn$;
END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 14. staff_read_athlete_data view/policy
-- ══════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
IF EXISTS (
  SELECT 1 FROM pg_policies
  WHERE tablename = 'sessions' AND policyname = 'staff_read_athlete_sessions'
) THEN
  EXECUTE 'DROP POLICY IF EXISTS "staff_read_athlete_sessions" ON public.sessions';
  EXECUTE $p$CREATE POLICY "staff_read_athlete_sessions" ON public.sessions FOR SELECT USING (
    user_id = auth.uid()
    OR user_id IN (
      SELECT cm_a.user_id FROM public.coaching_members cm_a
      WHERE cm_a.role = 'athlete'
        AND cm_a.group_id IN (
          SELECT cm2.group_id FROM public.coaching_members cm2
          WHERE cm2.user_id = auth.uid()
            AND cm2.role IN ('admin_master', 'coach', 'assistant')
        )
    )
  )$p$;
END IF;
END $$;
