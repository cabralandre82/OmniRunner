-- ============================================================================
-- OS-02: CRM do Atleta — Tags, Notas, Status, Segmentos
-- Tables, indexes, RLS for athlete CRM operations.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.coaching_tags (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (length(trim(name)) >= 1 AND length(trim(name)) <= 60),
  color       text CHECK (color IS NULL OR color ~ '^#[0-9a-fA-F]{6}$'),
  created_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_tag_group_name UNIQUE (group_id, name)
);

CREATE TABLE IF NOT EXISTS public.coaching_athlete_tags (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id         uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id  uuid NOT NULL REFERENCES auth.users(id),
  tag_id           uuid NOT NULL REFERENCES public.coaching_tags(id) ON DELETE CASCADE,
  created_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_athlete_tag UNIQUE (group_id, athlete_user_id, tag_id)
);

CREATE TABLE IF NOT EXISTS public.coaching_athlete_notes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id         uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id  uuid NOT NULL REFERENCES auth.users(id),
  created_by       uuid NOT NULL REFERENCES auth.users(id),
  note             text NOT NULL CHECK (length(trim(note)) >= 1),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coaching_member_status (
  group_id    uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id),
  status      text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'injured', 'inactive', 'trial')),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES auth.users(id),

  PRIMARY KEY (group_id, user_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. INDEXES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_tags_group
  ON public.coaching_tags (group_id);

CREATE INDEX IF NOT EXISTS idx_athlete_tags_group_athlete
  ON public.coaching_athlete_tags (group_id, athlete_user_id);

CREATE INDEX IF NOT EXISTS idx_athlete_tags_tag
  ON public.coaching_athlete_tags (tag_id);

CREATE INDEX IF NOT EXISTS idx_athlete_notes_group_athlete_time
  ON public.coaching_athlete_notes (group_id, athlete_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_member_status_group
  ON public.coaching_member_status (group_id, status);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_athlete_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_athlete_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_member_status ENABLE ROW LEVEL SECURITY;

-- ── coaching_tags ──

DROP POLICY IF EXISTS "tags_staff_read" ON public.coaching_tags;
CREATE POLICY "tags_staff_read" ON public.coaching_tags
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_tags.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

DROP POLICY IF EXISTS "tags_staff_insert" ON public.coaching_tags;
CREATE POLICY "tags_staff_insert" ON public.coaching_tags
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_tags.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

DROP POLICY IF EXISTS "tags_staff_update" ON public.coaching_tags;
CREATE POLICY "tags_staff_update" ON public.coaching_tags
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_tags.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

DROP POLICY IF EXISTS "tags_staff_delete" ON public.coaching_tags;
CREATE POLICY "tags_staff_delete" ON public.coaching_tags
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_tags.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ── coaching_athlete_tags ──

DROP POLICY IF EXISTS "athlete_tags_staff_read" ON public.coaching_athlete_tags;
CREATE POLICY "athlete_tags_staff_read" ON public.coaching_athlete_tags
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_tags.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

DROP POLICY IF EXISTS "athlete_tags_staff_insert" ON public.coaching_athlete_tags;
CREATE POLICY "athlete_tags_staff_insert" ON public.coaching_athlete_tags
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_tags.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

DROP POLICY IF EXISTS "athlete_tags_staff_delete" ON public.coaching_athlete_tags;
CREATE POLICY "athlete_tags_staff_delete" ON public.coaching_athlete_tags
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_tags.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- ── coaching_athlete_notes (staff-only, athlete CANNOT see) ──

DROP POLICY IF EXISTS "notes_staff_read" ON public.coaching_athlete_notes;
CREATE POLICY "notes_staff_read" ON public.coaching_athlete_notes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_notes.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

DROP POLICY IF EXISTS "notes_staff_insert" ON public.coaching_athlete_notes;
CREATE POLICY "notes_staff_insert" ON public.coaching_athlete_notes
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_notes.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

DROP POLICY IF EXISTS "notes_staff_delete" ON public.coaching_athlete_notes;
CREATE POLICY "notes_staff_delete" ON public.coaching_athlete_notes
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_notes.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ── coaching_member_status ──

DROP POLICY IF EXISTS "status_staff_read" ON public.coaching_member_status;
CREATE POLICY "status_staff_read" ON public.coaching_member_status
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_member_status.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

DROP POLICY IF EXISTS "status_self_read" ON public.coaching_member_status;
CREATE POLICY "status_self_read" ON public.coaching_member_status
  FOR SELECT USING (
    user_id = auth.uid()
  );

DROP POLICY IF EXISTS "status_staff_upsert" ON public.coaching_member_status;
CREATE POLICY "status_staff_upsert" ON public.coaching_member_status
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_member_status.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

DROP POLICY IF EXISTS "status_staff_update" ON public.coaching_member_status;
CREATE POLICY "status_staff_update" ON public.coaching_member_status
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_member_status.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ── Platform admin read-all ──

DROP POLICY IF EXISTS "tags_platform_admin_read" ON public.coaching_tags;
CREATE POLICY "tags_platform_admin_read" ON public.coaching_tags
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

DROP POLICY IF EXISTS "athlete_tags_platform_admin_read" ON public.coaching_athlete_tags;
CREATE POLICY "athlete_tags_platform_admin_read" ON public.coaching_athlete_tags
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

DROP POLICY IF EXISTS "notes_platform_admin_read" ON public.coaching_athlete_notes;
CREATE POLICY "notes_platform_admin_read" ON public.coaching_athlete_notes
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

DROP POLICY IF EXISTS "status_platform_admin_read" ON public.coaching_member_status;
CREATE POLICY "status_platform_admin_read" ON public.coaching_member_status
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPC: fn_upsert_member_status (idempotent)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_upsert_member_status(
  p_group_id  uuid,
  p_user_id   uuid,
  p_status    text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = v_uid
      AND role IN ('admin_master', 'coach')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_STAFF');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = p_user_id
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'USER_NOT_IN_GROUP');
  END IF;

  INSERT INTO public.coaching_member_status (group_id, user_id, status, updated_by, updated_at)
  VALUES (p_group_id, p_user_id, p_status, v_uid, now())
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET status = EXCLUDED.status, updated_by = EXCLUDED.updated_by, updated_at = now();

  RETURN jsonb_build_object('ok', true, 'status', p_status);
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_upsert_member_status(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_upsert_member_status(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_upsert_member_status(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_upsert_member_status(uuid, uuid, text) TO service_role;

COMMIT;
