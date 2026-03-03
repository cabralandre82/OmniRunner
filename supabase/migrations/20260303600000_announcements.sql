-- ============================================================================
-- OS-03: Comunicação — Mural/Avisos + Confirmação de Leitura
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.coaching_announcements (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  created_by  uuid NOT NULL REFERENCES auth.users(id),
  title       text NOT NULL CHECK (length(trim(title)) >= 2 AND length(trim(title)) <= 200),
  body        text NOT NULL CHECK (length(trim(body)) >= 1),
  pinned      boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coaching_announcement_reads (
  announcement_id uuid NOT NULL REFERENCES public.coaching_announcements(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id),
  read_at         timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (announcement_id, user_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. INDEXES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_announcements_group_time
  ON public.coaching_announcements (group_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_announcements_group_pinned
  ON public.coaching_announcements (group_id, pinned DESC, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_announcement_reads_announcement
  ON public.coaching_announcement_reads (announcement_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_announcement_reads ENABLE ROW LEVEL SECURITY;

-- All group members can read announcements
CREATE POLICY "announcements_member_read"
  ON public.coaching_announcements FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_announcements.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- Staff can create announcements
CREATE POLICY "announcements_staff_insert"
  ON public.coaching_announcements FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_announcements.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- Staff can update (edit/pin) announcements
CREATE POLICY "announcements_staff_update"
  ON public.coaching_announcements FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_announcements.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- Staff can delete announcements
CREATE POLICY "announcements_staff_delete"
  ON public.coaching_announcements FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_announcements.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- User can mark their own read
CREATE POLICY "reads_self_insert"
  ON public.coaching_announcement_reads FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.coaching_announcements a
      JOIN public.coaching_members cm ON cm.group_id = a.group_id AND cm.user_id = auth.uid()
      WHERE a.id = coaching_announcement_reads.announcement_id
    )
  );

-- User can see their own reads
CREATE POLICY "reads_self_select"
  ON public.coaching_announcement_reads FOR SELECT USING (
    user_id = auth.uid()
  );

-- Staff can see all reads for announcements in their group (aggregates)
CREATE POLICY "reads_staff_select"
  ON public.coaching_announcement_reads FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_announcements a
      JOIN public.coaching_members cm ON cm.group_id = a.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
      WHERE a.id = coaching_announcement_reads.announcement_id
    )
  );

-- Platform admin
CREATE POLICY "announcements_platform_admin_read"
  ON public.coaching_announcements FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

CREATE POLICY "reads_platform_admin_read"
  ON public.coaching_announcement_reads FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPC: fn_mark_announcement_read (idempotent)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_mark_announcement_read(
  p_announcement_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid      uuid;
  v_group_id uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  SELECT group_id INTO v_group_id
    FROM public.coaching_announcements
    WHERE id = p_announcement_id;

  IF v_group_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ANNOUNCEMENT_NOT_FOUND');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_group_id AND user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_IN_GROUP');
  END IF;

  INSERT INTO public.coaching_announcement_reads (announcement_id, user_id)
  VALUES (p_announcement_id, v_uid)
  ON CONFLICT (announcement_id, user_id) DO NOTHING;

  RETURN jsonb_build_object('ok', true);
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_mark_announcement_read(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_mark_announcement_read(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_mark_announcement_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mark_announcement_read(uuid) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. RPC: fn_announcement_read_stats (for staff)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_announcement_read_stats(
  p_announcement_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid          uuid;
  v_group_id     uuid;
  v_total        int;
  v_read_count   int;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  SELECT group_id INTO v_group_id
    FROM public.coaching_announcements
    WHERE id = p_announcement_id;

  IF v_group_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ANNOUNCEMENT_NOT_FOUND');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_group_id AND user_id = v_uid
      AND role IN ('admin_master', 'coach', 'assistant')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_STAFF');
  END IF;

  SELECT count(*) INTO v_total
    FROM public.coaching_members
    WHERE group_id = v_group_id;

  SELECT count(*) INTO v_read_count
    FROM public.coaching_announcement_reads
    WHERE announcement_id = p_announcement_id;

  RETURN jsonb_build_object(
    'ok', true,
    'total_members', v_total,
    'read_count', v_read_count,
    'read_rate', CASE WHEN v_total > 0 THEN round((v_read_count::numeric / v_total) * 100, 1) ELSE 0 END
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_announcement_read_stats(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_announcement_read_stats(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_announcement_read_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_announcement_read_stats(uuid) TO service_role;

COMMIT;
