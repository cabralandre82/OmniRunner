-- ============================================================================
-- L21-12 — Staff team dashboard primitives (specialist roles + permissions)
-- Date: 2026-04-21
-- ============================================================================
-- Finding: an elite athlete is supported by a *team*: coach + physiologist +
-- physiotherapist + nutritionist + sports psychologist. The current
-- `coaching_members.role` CHECK only accepts
-- `{admin_master, coach, assistant, athlete}` — there is no way to grant a
-- physio access to an athlete's runs without promoting them to `assistant`
-- (which grants them everything an assistant can do). This migration ships
-- the canonical primitives:
--
--   1. Extends `coaching_members.role` CHECK to include three specialist
--      roles: `physio`, `nutritionist`, `psychologist`. Existing rows are
--      untouched (additive change).
--   2. Introduces `public.role_permissions` as the single source of truth
--      for which permissions each role holds. Seeded with the canonical
--      matrix for the six current roles (admin_master, coach, assistant,
--      physio, nutritionist, psychologist, athlete). `platform_admin`
--      manages the table; everyone can SELECT.
--   3. `fn_role_has_permission(role, permission)` STABLE function that
--      existing RLS + SECURITY DEFINER RPCs can consume incrementally
--      without rewriting every `role IN (…)` string.
--   4. `fn_is_staff_role(role)` IMMUTABLE helper (TRUE for everything
--      except `athlete`). Used by the new per-athlete view grant check.
--   5. `public.athlete_staff_access` table — per-(athlete, staff,
--      permission) grant so an athlete can explicitly open their
--      nutrition log to ONE nutritionist without making every
--      nutritionist in the group see it. Grants are athlete-controlled
--      (RLS: athlete can INSERT/DELETE own rows), staff can read rows
--      where they are the staff, platform_admin reads everything.
--   6. `fn_my_role_in_group_ext(group_id)` SECURITY DEFINER — returns
--      a jsonb `{ role, permissions }` payload the portal / mobile
--      clients can use to render the right tabs without re-querying per
--      permission.
--
-- Additive only — no destructive change. All existing CHECK-bound SQL
-- continues to match because we EXPANDED the allowed set; we did not
-- remove any value.

BEGIN;

-- ── 0. Expand coaching_members.role CHECK ───────────────────────────────

-- The constraint was declared inline in 20260218000000_full_schema.sql and
-- named implicitly. Drop whichever name is present and re-add the expanded
-- set.
DO $cm_role$
DECLARE
  v_conname TEXT;
BEGIN
  SELECT conname INTO v_conname
  FROM pg_constraint
  WHERE conrelid = 'public.coaching_members'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%role%'
  LIMIT 1;
  IF v_conname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.coaching_members DROP CONSTRAINT %I', v_conname);
  END IF;
END;
$cm_role$;

ALTER TABLE public.coaching_members
  ADD CONSTRAINT coaching_members_role_check CHECK (
    role IN ('admin_master','coach','assistant','physio','nutritionist','psychologist','athlete')
  );

-- ── 1. Role helpers ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_is_staff_role(p_role TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
BEGIN
  RETURN p_role IS NOT NULL
    AND p_role IN ('admin_master','coach','assistant','physio','nutritionist','psychologist');
END;
$$;

COMMENT ON FUNCTION public.fn_is_staff_role(TEXT) IS
  'Returns true for any non-athlete coaching_members role. Abstracts the staff-role list so new specialist roles can be added without touching every caller.';

GRANT EXECUTE ON FUNCTION public.fn_is_staff_role(TEXT) TO PUBLIC;

-- ── 2. role_permissions catalogue ───────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.role_permissions (
  role        TEXT NOT NULL,
  permission  TEXT NOT NULL,
  granted     BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (role, permission),
  CONSTRAINT role_permissions_role_check CHECK (
    role IN ('admin_master','coach','assistant','physio','nutritionist','psychologist','athlete')
  ),
  CONSTRAINT role_permissions_permission_shape CHECK (
    permission ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  )
);

COMMENT ON TABLE public.role_permissions IS
  'L21-12: canonical matrix of (role → permission) grants. Seeded with the default policy; platform_admin can tweak. Consumed by fn_role_has_permission.';

ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS role_permissions_public_read ON public.role_permissions;
CREATE POLICY role_permissions_public_read ON public.role_permissions
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS role_permissions_platform_admin_write ON public.role_permissions;
CREATE POLICY role_permissions_platform_admin_write ON public.role_permissions
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

-- Seed canonical matrix (idempotent).
INSERT INTO public.role_permissions (role, permission, granted) VALUES
  -- admin_master has everything.
  ('admin_master', 'training_plan.manage', TRUE),
  ('admin_master', 'training_plan.read', TRUE),
  ('admin_master', 'athlete.billing.manage', TRUE),
  ('admin_master', 'athlete.health.read', TRUE),
  ('admin_master', 'athlete.health.notes.write', TRUE),
  ('admin_master', 'athlete.nutrition.read', TRUE),
  ('admin_master', 'athlete.nutrition.write', TRUE),
  ('admin_master', 'athlete.mental.read', TRUE),
  ('admin_master', 'athlete.mental.write', TRUE),
  ('admin_master', 'group.branding.manage', TRUE),
  ('admin_master', 'group.custom_domain.manage', TRUE),
  ('admin_master', 'group.webhook.manage', TRUE),

  -- coach: everything except billing/webhook/domain (those are admin_master only).
  ('coach', 'training_plan.manage', TRUE),
  ('coach', 'training_plan.read', TRUE),
  ('coach', 'athlete.health.read', TRUE),
  ('coach', 'athlete.health.notes.write', TRUE),
  ('coach', 'athlete.nutrition.read', TRUE),
  ('coach', 'athlete.mental.read', TRUE),

  -- assistant: read-mostly on training, no health access by default.
  ('assistant', 'training_plan.read', TRUE),
  ('assistant', 'athlete.health.read', TRUE),

  -- physio: full health read, write ONLY on the physio notes sub-surface,
  -- nothing on nutrition / psych.
  ('physio', 'training_plan.read', TRUE),
  ('physio', 'athlete.health.read', TRUE),
  ('physio', 'athlete.health.notes.write', TRUE),

  -- nutritionist: nutrition only.
  ('nutritionist', 'athlete.nutrition.read', TRUE),
  ('nutritionist', 'athlete.nutrition.write', TRUE),

  -- psychologist: mental only.
  ('psychologist', 'athlete.mental.read', TRUE),
  ('psychologist', 'athlete.mental.write', TRUE),

  -- athlete: read own data.
  ('athlete', 'training_plan.read', TRUE),
  ('athlete', 'athlete.health.read', TRUE),
  ('athlete', 'athlete.nutrition.read', TRUE),
  ('athlete', 'athlete.mental.read', TRUE)
ON CONFLICT (role, permission) DO NOTHING;

-- ── 3. fn_role_has_permission ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_role_has_permission(p_role TEXT, p_permission TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
  v_granted BOOLEAN;
BEGIN
  IF p_role IS NULL OR p_permission IS NULL THEN
    RETURN FALSE;
  END IF;
  SELECT granted INTO v_granted
  FROM public.role_permissions
  WHERE role = p_role AND permission = p_permission;
  RETURN COALESCE(v_granted, FALSE);
END;
$$;

COMMENT ON FUNCTION public.fn_role_has_permission(TEXT, TEXT) IS
  'Returns true when (role, permission) is granted in role_permissions. STABLE because role_permissions can be tweaked by platform_admin at runtime.';

GRANT EXECUTE ON FUNCTION public.fn_role_has_permission(TEXT, TEXT) TO PUBLIC;

-- ── 4. athlete_staff_access: athlete-controlled per-staff grants ────────

CREATE TABLE IF NOT EXISTS public.athlete_staff_access (
  athlete_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  staff_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission   TEXT NOT NULL,
  granted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at   TIMESTAMPTZ,
  PRIMARY KEY (athlete_id, staff_id, permission),
  CONSTRAINT athlete_staff_access_permission_shape CHECK (
    permission ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  ),
  CONSTRAINT athlete_staff_access_timestamp_order CHECK (
    revoked_at IS NULL OR revoked_at >= granted_at
  )
);

CREATE INDEX IF NOT EXISTS athlete_staff_access_staff_idx
  ON public.athlete_staff_access (staff_id)
  WHERE revoked_at IS NULL;

COMMENT ON TABLE public.athlete_staff_access IS
  'L21-12: per-(athlete, staff, permission) grant. Athlete-controlled: athletes open specific sub-surfaces of their profile (nutrition/mental/health) to ONE staff of each specialty without making every specialist in the group see it.';

ALTER TABLE public.athlete_staff_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS athlete_staff_access_own ON public.athlete_staff_access;
CREATE POLICY athlete_staff_access_own ON public.athlete_staff_access
  FOR ALL USING (athlete_id = auth.uid())
  WITH CHECK (athlete_id = auth.uid());

DROP POLICY IF EXISTS athlete_staff_access_staff_read ON public.athlete_staff_access;
CREATE POLICY athlete_staff_access_staff_read ON public.athlete_staff_access
  FOR SELECT USING (staff_id = auth.uid());

DROP POLICY IF EXISTS athlete_staff_access_platform_admin ON public.athlete_staff_access;
CREATE POLICY athlete_staff_access_platform_admin ON public.athlete_staff_access
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

-- ── 5. fn_my_role_in_group_ext ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_my_role_in_group_ext(p_group_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role TEXT;
  v_permissions TEXT[];
BEGIN
  SELECT role INTO v_role
  FROM public.coaching_members
  WHERE group_id = p_group_id AND user_id = auth.uid();

  IF v_role IS NULL THEN
    RETURN jsonb_build_object('role', NULL, 'permissions', '[]'::jsonb);
  END IF;

  SELECT coalesce(array_agg(permission ORDER BY permission), ARRAY[]::text[])
  INTO v_permissions
  FROM public.role_permissions
  WHERE role = v_role AND granted = TRUE;

  RETURN jsonb_build_object(
    'role', v_role,
    'is_staff', public.fn_is_staff_role(v_role),
    'permissions', to_jsonb(v_permissions)
  );
END;
$$;

COMMENT ON FUNCTION public.fn_my_role_in_group_ext(UUID) IS
  'Returns the caller role in the group + the full granted-permission list in one round-trip. Clients render staff dashboards from this payload.';

REVOKE ALL ON FUNCTION public.fn_my_role_in_group_ext(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_my_role_in_group_ext(UUID) TO authenticated, service_role;

-- ── 6. Self-test ────────────────────────────────────────────────────────

DO $self_test$
BEGIN
  IF NOT public.fn_is_staff_role('physio') THEN
    RAISE EXCEPTION 'self-test: fn_is_staff_role rejected physio';
  END IF;
  IF public.fn_is_staff_role('athlete') THEN
    RAISE EXCEPTION 'self-test: fn_is_staff_role accepted athlete';
  END IF;
  IF public.fn_is_staff_role(NULL) THEN
    RAISE EXCEPTION 'self-test: fn_is_staff_role accepted NULL';
  END IF;

  IF NOT public.fn_role_has_permission('coach', 'athlete.health.read') THEN
    RAISE EXCEPTION 'self-test: coach must have athlete.health.read';
  END IF;
  IF public.fn_role_has_permission('nutritionist', 'athlete.mental.write') THEN
    RAISE EXCEPTION 'self-test: nutritionist must NOT have athlete.mental.write';
  END IF;
  IF public.fn_role_has_permission('physio', 'athlete.nutrition.write') THEN
    RAISE EXCEPTION 'self-test: physio must NOT have athlete.nutrition.write';
  END IF;
  IF NOT public.fn_role_has_permission('psychologist', 'athlete.mental.write') THEN
    RAISE EXCEPTION 'self-test: psychologist must have athlete.mental.write';
  END IF;
  IF public.fn_role_has_permission('athlete', 'training_plan.manage') THEN
    RAISE EXCEPTION 'self-test: athlete must NOT have training_plan.manage';
  END IF;

  PERFORM 1 FROM pg_constraint
   WHERE conrelid = 'public.coaching_members'::regclass
     AND conname = 'coaching_members_role_check';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'self-test: coaching_members_role_check missing after expansion';
  END IF;

  RAISE NOTICE 'L21-12 self-test OK';
END;
$self_test$;

COMMIT;
