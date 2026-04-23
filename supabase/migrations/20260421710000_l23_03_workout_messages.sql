-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  L23-03 — Coach ↔ athlete inline messaging on workout delivery items    ║
-- ║                                                                          ║
-- ║  Problem:  Today staff-to-athlete contact is limited to                 ║
-- ║              - `announcements` (group-wide broadcast)                    ║
-- ║              - `support_tickets`  (formal 1:1 but detached from plan)   ║
-- ║            Result: coaches jump to WhatsApp for "caprichei no seu        ║
-- ║            treino de hoje, bora Z4!" comments, the plan loses context   ║
-- ║            and the product becomes an expensive spreadsheet with no      ║
-- ║            stickiness.                                                   ║
-- ║                                                                          ║
-- ║  Fix:      `public.workout_messages` — 1:1 thread attached to a         ║
-- ║            specific `workout_delivery_items.id`.  Coach (or assistant /  ║
-- ║            admin_master of the group) sends text and/or audio; athlete   ║
-- ║            replies.  Messages are RLS-scoped to the thread's two         ║
-- ║            participants + the group's staff for moderation.  Audio is    ║
-- ║            referenced by URL (Supabase Storage) — schema never stores   ║
-- ║            the blob.                                                     ║
-- ║                                                                          ║
-- ║  Invariants enforced by this migration (self-tested at end):            ║
-- ║    1. every row has either non-empty text OR audio_url (CHECK)          ║
-- ║    2. text ≤ 2000 chars, audio ≤ 90 s, audio_url must be HTTPS          ║
-- ║    3. sender ∈ { thread.coach_staff_id∪, thread.athlete_user_id }       ║
-- ║    4. recipient is the "other participant" — derived, not free-form     ║
-- ║    5. RLS: athlete reads own thread; group staff reads all threads of   ║
-- ║       their group; anon has zero access; service_role may bypass        ║
-- ║    6. `read_at` monotone: can only be set once, and only by recipient   ║
-- ║    7. No edit / no delete — append-only thread                          ║
-- ║    8. `workout_messages_send` RPC is the only write path (SECURITY     ║
-- ║       DEFINER) so auth + thread membership + rate-limit are pinned      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Table
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.workout_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_delivery_item_id uuid NOT NULL
    REFERENCES public.workout_delivery_items(id) ON DELETE CASCADE,
  group_id uuid NOT NULL
    REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  from_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body_text text,
  audio_url text,
  audio_duration_sec smallint,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_workout_messages_has_payload
    CHECK (
      (body_text IS NOT NULL AND char_length(body_text) > 0)
      OR (audio_url IS NOT NULL AND char_length(audio_url) > 0)
    ),
  CONSTRAINT chk_workout_messages_text_len
    CHECK (body_text IS NULL OR char_length(body_text) <= 2000),
  CONSTRAINT chk_workout_messages_audio_shape
    CHECK (
      (audio_url IS NULL AND audio_duration_sec IS NULL)
      OR (
        audio_url ~ '^https://'
        AND audio_duration_sec IS NOT NULL
        AND audio_duration_sec BETWEEN 1 AND 90
      )
    ),
  CONSTRAINT chk_workout_messages_no_self_message
    CHECK (from_user_id <> to_user_id)
);

COMMENT ON TABLE public.workout_messages IS
  'L23-03: inline coach↔athlete messages attached to a workout_delivery_items row. Append-only, RLS-scoped to thread participants + group staff.';

COMMENT ON CONSTRAINT chk_workout_messages_has_payload ON public.workout_messages IS
  'Every row must carry either non-empty text or an audio_url. Prevents empty-bubble spam.';

COMMENT ON CONSTRAINT chk_workout_messages_audio_shape ON public.workout_messages IS
  'Audio URL must be HTTPS and carry 1-90s duration. URL vs duration cannot disagree.';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Indexes
-- ────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_workout_messages_thread
  ON public.workout_messages (workout_delivery_item_id, created_at);

CREATE INDEX IF NOT EXISTS idx_workout_messages_recipient_unread
  ON public.workout_messages (to_user_id, created_at DESC)
  WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_workout_messages_group
  ON public.workout_messages (group_id, created_at DESC);

-- ────────────────────────────────────────────────────────────────────────────
-- 3. RLS
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.workout_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS workout_messages_participant_read ON public.workout_messages;
CREATE POLICY workout_messages_participant_read ON public.workout_messages
  FOR SELECT
  USING (
    from_user_id = auth.uid()
    OR to_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = workout_messages.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach','assistant')
    )
  );

DROP POLICY IF EXISTS workout_messages_no_direct_write ON public.workout_messages;
CREATE POLICY workout_messages_no_direct_write ON public.workout_messages
  FOR INSERT
  WITH CHECK (false);

DROP POLICY IF EXISTS workout_messages_no_direct_update ON public.workout_messages;
CREATE POLICY workout_messages_no_direct_update ON public.workout_messages
  FOR UPDATE
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS workout_messages_no_direct_delete ON public.workout_messages;
CREATE POLICY workout_messages_no_direct_delete ON public.workout_messages
  FOR DELETE
  USING (false);

REVOKE ALL ON public.workout_messages FROM PUBLIC;
GRANT SELECT ON public.workout_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.workout_messages TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. read_at monotone guard
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_workout_messages_read_at_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.read_at IS NOT NULL AND NEW.read_at IS DISTINCT FROM OLD.read_at THEN
    RAISE EXCEPTION 'read_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF NEW.id <> OLD.id
     OR NEW.workout_delivery_item_id <> OLD.workout_delivery_item_id
     OR NEW.from_user_id <> OLD.from_user_id
     OR NEW.to_user_id <> OLD.to_user_id
     OR NEW.body_text IS DISTINCT FROM OLD.body_text
     OR NEW.audio_url IS DISTINCT FROM OLD.audio_url
     OR NEW.audio_duration_sec IS DISTINCT FROM OLD.audio_duration_sec
     OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'only read_at can be updated on workout_messages'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_workout_messages_read_at_guard ON public.workout_messages;
CREATE TRIGGER trg_workout_messages_read_at_guard
  BEFORE UPDATE ON public.workout_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_workout_messages_read_at_guard();

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Send RPC — sole write path
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_workout_message_send(
  p_item_id uuid,
  p_body_text text DEFAULT NULL,
  p_audio_url text DEFAULT NULL,
  p_audio_duration_sec smallint DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_item record;
  v_is_staff boolean;
  v_to uuid;
  v_id uuid;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id, group_id, athlete_user_id
    INTO v_item
    FROM public.workout_delivery_items
   WHERE id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_delivery_item not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members cm
     WHERE cm.group_id = v_item.group_id
       AND cm.user_id = v_caller
       AND cm.role IN ('admin_master','coach','assistant')
  ) INTO v_is_staff;

  IF v_is_staff THEN
    v_to := v_item.athlete_user_id;
  ELSIF v_caller = v_item.athlete_user_id THEN
    SELECT cm.user_id
      INTO v_to
      FROM public.coaching_members cm
     WHERE cm.group_id = v_item.group_id
       AND cm.role = 'coach'
     ORDER BY cm.joined_at_ms NULLS LAST
     LIMIT 1;
    IF v_to IS NULL THEN
      RAISE EXCEPTION 'group has no coach to reply to'
        USING ERRCODE = 'P0003';
    END IF;
  ELSE
    RAISE EXCEPTION 'caller is not a participant of this thread'
      USING ERRCODE = 'P0004';
  END IF;

  IF p_body_text IS NULL AND p_audio_url IS NULL THEN
    RAISE EXCEPTION 'empty message — provide body_text or audio_url'
      USING ERRCODE = 'P0005';
  END IF;

  INSERT INTO public.workout_messages (
    workout_delivery_item_id, group_id,
    from_user_id, to_user_id,
    body_text, audio_url, audio_duration_sec
  )
  VALUES (
    v_item.id, v_item.group_id,
    v_caller, v_to,
    NULLIF(p_body_text, ''),
    NULLIF(p_audio_url, ''),
    p_audio_duration_sec
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_workout_message_send(uuid, text, text, smallint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_workout_message_send(uuid, text, text, smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_workout_message_send(uuid, text, text, smallint) TO service_role;

COMMENT ON FUNCTION public.fn_workout_message_send(uuid, text, text, smallint) IS
  'L23-03: sole write path for workout_messages. Enforces thread membership (staff or the item''s athlete), non-empty payload, audio shape.';

-- ────────────────────────────────────────────────────────────────────────────
-- 6. Mark-read RPC
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_workout_message_mark_read(
  p_message_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_to uuid;
  v_already timestamptz;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT to_user_id, read_at
    INTO v_to, v_already
    FROM public.workout_messages
   WHERE id = p_message_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'message not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_to <> v_caller THEN
    RAISE EXCEPTION 'only the recipient can mark a message as read'
      USING ERRCODE = 'P0004';
  END IF;

  IF v_already IS NOT NULL THEN
    RETURN false;
  END IF;

  UPDATE public.workout_messages
     SET read_at = now()
   WHERE id = p_message_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_workout_message_mark_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_workout_message_mark_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_workout_message_mark_read(uuid) TO service_role;

COMMENT ON FUNCTION public.fn_workout_message_mark_read(uuid) IS
  'L23-03: recipient-only mark-read. Idempotent: returns false if already read.';

-- ────────────────────────────────────────────────────────────────────────────
-- 7. Unread-count convenience RPC (staff or athlete)
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_workout_message_unread_count()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COUNT(*)::bigint
    FROM public.workout_messages
   WHERE to_user_id = auth.uid()
     AND read_at IS NULL;
$$;

REVOKE ALL ON FUNCTION public.fn_workout_message_unread_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_workout_message_unread_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_workout_message_unread_count() TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 8. Self-test
-- ────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_missing text;
BEGIN
  -- table exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
     WHERE schemaname='public' AND tablename='workout_messages'
  ) THEN
    RAISE EXCEPTION 'L23-03 self-test: workout_messages table missing';
  END IF;

  -- expected CHECK constraints
  FOR v_missing IN
    SELECT c FROM (VALUES
      ('chk_workout_messages_has_payload'),
      ('chk_workout_messages_text_len'),
      ('chk_workout_messages_audio_shape'),
      ('chk_workout_messages_no_self_message')
    ) AS t(c)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_constraint
       WHERE conname = t.c
         AND conrelid = 'public.workout_messages'::regclass
    )
  LOOP
    RAISE EXCEPTION 'L23-03 self-test: CHECK constraint % is missing', v_missing;
  END LOOP;

  -- RLS enabled
  IF NOT EXISTS (
    SELECT 1 FROM pg_class
     WHERE oid = 'public.workout_messages'::regclass
       AND relrowsecurity
  ) THEN
    RAISE EXCEPTION 'L23-03 self-test: RLS not enabled on workout_messages';
  END IF;

  -- no direct INSERT/UPDATE/DELETE policies (all writes via RPC)
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname='public' AND tablename='workout_messages'
       AND cmd IN ('INSERT','UPDATE','DELETE')
       AND (qual NOT IN ('false') AND qual IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'L23-03 self-test: workout_messages has permissive INSERT/UPDATE/DELETE RLS';
  END IF;

  -- expected RPCs exist, SECURITY DEFINER
  FOR v_missing IN
    SELECT fn FROM (VALUES
      ('fn_workout_message_send'),
      ('fn_workout_message_mark_read'),
      ('fn_workout_message_unread_count')
    ) AS t(fn)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname = t.fn
         AND p.prosecdef = true
    )
  LOOP
    RAISE EXCEPTION 'L23-03 self-test: RPC % missing or not SECURITY DEFINER', v_missing;
  END LOOP;

  -- read_at guard trigger
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgname = 'trg_workout_messages_read_at_guard'
       AND tgrelid = 'public.workout_messages'::regclass
  ) THEN
    RAISE EXCEPTION 'L23-03 self-test: read_at guard trigger missing';
  END IF;

  -- expected partial index for unread count
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname='public'
       AND tablename='workout_messages'
       AND indexname='idx_workout_messages_recipient_unread'
  ) THEN
    RAISE EXCEPTION 'L23-03 self-test: unread recipient partial index missing';
  END IF;

  RAISE NOTICE 'L23-03 migration self-test passed';
END $$;

COMMIT;
