-- UZ-002: Restrict challenges RLS to participants + group members
DO $$
BEGIN
  DROP POLICY IF EXISTS "challenges_select_authenticated" ON "public"."challenges";
  DROP POLICY IF EXISTS "challenges_select_group_or_participant" ON "public"."challenges";
  CREATE POLICY "challenges_select_group_or_participant" ON "public"."challenges"
    FOR SELECT USING (
      auth.uid() = created_by
      OR EXISTS (
        SELECT 1 FROM challenge_participants cp WHERE cp.challenge_id = challenges.id AND cp.user_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1 FROM coaching_members cm WHERE cm.group_id = challenges.group_id AND cm.user_id = auth.uid()
      )
    );
EXCEPTION WHEN undefined_table THEN NULL;
  WHEN undefined_column THEN NULL;
END $$;

-- UZ-027: Fix conflicting RLS on badge_awards and profile_progress
DO $$
BEGIN
  DROP POLICY IF EXISTS "badge_awards_public_read" ON "public"."badge_awards";
  DROP POLICY IF EXISTS "badge_awards_group_read" ON "public"."badge_awards";
  CREATE POLICY "badge_awards_group_read" ON "public"."badge_awards"
    FOR SELECT USING (
      auth.uid() = user_id
      OR EXISTS (
        SELECT 1 FROM coaching_members cm1
        JOIN coaching_members cm2 ON cm1.group_id = cm2.group_id
        WHERE cm1.user_id = auth.uid() AND cm2.user_id = badge_awards.user_id
      )
    );
EXCEPTION WHEN undefined_table THEN NULL;
  WHEN undefined_column THEN NULL;
END $$;

DO $$
BEGIN
  DROP POLICY IF EXISTS "progress_public_read" ON "public"."profile_progress";
  DROP POLICY IF EXISTS "progress_group_read" ON "public"."profile_progress";
  CREATE POLICY "progress_group_read" ON "public"."profile_progress"
    FOR SELECT USING (
      auth.uid() = user_id
      OR EXISTS (
        SELECT 1 FROM coaching_members cm1
        JOIN coaching_members cm2 ON cm1.group_id = cm2.group_id
        WHERE cm1.user_id = auth.uid() AND cm2.user_id = profile_progress.user_id
      )
    );
EXCEPTION WHEN undefined_table THEN NULL;
  WHEN undefined_column THEN NULL;
END $$;

-- UZ-065: Scope events to authenticated users only
DO $$
BEGIN
  DROP POLICY IF EXISTS "events_read_all" ON "public"."events";
  DROP POLICY IF EXISTS "events_read_authenticated" ON "public"."events";
  CREATE POLICY "events_read_authenticated" ON "public"."events"
    FOR SELECT USING (
      auth.role() = 'authenticated'
    );
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- UZ-013: Ensure account deletion covers all user data
CREATE OR REPLACE FUNCTION fn_delete_user_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Anonymize financial records (keep for audit trail but remove PII link)
  BEGIN UPDATE coin_ledger SET user_id = '00000000-0000-0000-0000-000000000000'::uuid WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;

  BEGIN DELETE FROM sessions WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM challenge_participants WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM badge_awards WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM profile_progress WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM coaching_athlete_kpis_daily WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM wallets WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM notification_log WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM strava_connections WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM coaching_members WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM leaderboard_entries WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM workout_delivery_items WHERE athlete_user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM support_tickets WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; WHEN undefined_column THEN NULL; END;

  -- Anonymize profile
  UPDATE profiles SET
    display_name = 'Conta Removida',
    avatar_url = NULL,
    bio = NULL,
    email = NULL,
    phone = NULL,
    instagram_handle = NULL,
    strava_athlete_id = NULL,
    updated_at = now()
  WHERE id = p_user_id;
END;
$$;

-- UZ-041: Add notification trigger for verification status changes
DO $$
BEGIN
  CREATE OR REPLACE FUNCTION fn_notify_verification_change()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $fn$
  BEGIN
    IF NEW.verification_status IS DISTINCT FROM OLD.verification_status THEN
      INSERT INTO notification_log (user_id, type, title, body, meta)
      VALUES (
        NEW.user_id,
        'verification_update',
        'Verificação atualizada',
        CASE NEW.verification_status
          WHEN 'VERIFIED' THEN 'Sua verificação foi aprovada!'
          WHEN 'DOWNGRADED' THEN 'Sua verificação precisa de ajustes.'
          ELSE 'O status da sua verificação foi atualizado.'
        END,
        jsonb_build_object('status', NEW.verification_status, 'user_id', NEW.user_id)
      );
    END IF;
    RETURN NEW;
  END;
  $fn$;

  DROP TRIGGER IF EXISTS trg_notify_verification_change ON public.athlete_verification;
  CREATE TRIGGER trg_notify_verification_change
    AFTER UPDATE ON public.athlete_verification
    FOR EACH ROW
    EXECUTE FUNCTION fn_notify_verification_change();
EXCEPTION WHEN undefined_table THEN NULL;
END $$;
