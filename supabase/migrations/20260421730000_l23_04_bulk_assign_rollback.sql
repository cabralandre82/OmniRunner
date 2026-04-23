-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ L23-04 — Bulk-assign rollback (undo-last-batch)                          ║
-- ║                                                                           ║
-- ║ Finding : docs/audit/findings/L23-04-bulk-assign-semanal-ver-           ║
-- ║           20260416000000-bulk-assign-and.md                               ║
-- ║                                                                           ║
-- ║ Problema                                                                  ║
-- ║ --------                                                                  ║
-- ║ `fn_bulk_assign_week` (migration 20260416000000) cria dezenas de          ║
-- ║ `plan_workout_releases` + uma `training_plan_weeks` por atleta, sem      ║
-- ║ qualquer identificador que permita desfazer o lote atomicamente.          ║
-- ║ Coach que atribui errado para 300 atletas fica sem recurso.               ║
-- ║                                                                           ║
-- ║ Solução                                                                   ║
-- ║ -------                                                                   ║
-- ║ Additive, backward-compatible:                                            ║
-- ║                                                                           ║
-- ║   1. Tabela `public.bulk_assign_batches` registra cada lote.              ║
-- ║   2. Coluna opcional `bulk_batch_id` em `plan_workout_releases` e        ║
-- ║      `training_plan_weeks` vinculando linhas ao lote.                     ║
-- ║   3. RPC `fn_bulk_assign_batch_open(...)` abre um batch.                 ║
-- ║   4. RPC `fn_bulk_assign_batch_attach(...)` associa releases criados.   ║
-- ║   5. RPC `fn_bulk_assign_batch_undo(...)` cancela atomicamente dentro    ║
-- ║      de um TTL (default 60 min), com auth gating (coach/admin do grupo    ║
-- ║      E autor do lote ou platform_admin).                                  ║
-- ║   6. RPC `fn_bulk_assign_batch_summary(...)` informa "ainda dá pra       ║
-- ║      desfazer?" para habilitar/desabilitar botão no UI.                   ║
-- ║                                                                           ║
-- ║ OmniCoin                                                                  ║
-- ║ --------                                                                  ║
-- ║ Nenhum RPC toca public.coin_ledger / public.wallets. L04-07-OK            ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Schema
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.bulk_assign_batches (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid NOT NULL REFERENCES public.coaching_groups(id),
  actor_id          uuid NOT NULL REFERENCES auth.users(id),
  description       text,
  items_count       int  NOT NULL DEFAULT 0 CHECK (items_count >= 0),
  undo_ttl_minutes  int  NOT NULL DEFAULT 60
    CHECK (undo_ttl_minutes BETWEEN 1 AND 1440),
  created_at        timestamptz NOT NULL DEFAULT now(),
  undone_at         timestamptz,
  undone_by         uuid REFERENCES auth.users(id),
  undo_reason       text,
  CONSTRAINT bulk_assign_batches_undone_consistency
    CHECK (
      (undone_at IS NULL AND undone_by IS NULL)
      OR (undone_at IS NOT NULL AND undone_by IS NOT NULL)
    )
);

COMMENT ON TABLE public.bulk_assign_batches IS
  'L23-04: registro por lote de bulk-assign, permitindo undo atômico '
  'dentro de TTL configurável. Nunca é modificada após undone_at ser '
  'setado — append-like. Não intermedia OmniCoins.';

CREATE INDEX IF NOT EXISTS bulk_assign_batches_group_recent
  ON public.bulk_assign_batches (group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS bulk_assign_batches_actor_recent
  ON public.bulk_assign_batches (actor_id, created_at DESC);

-- Colunas aditivas nas tabelas de payload
ALTER TABLE public.plan_workout_releases
  ADD COLUMN IF NOT EXISTS bulk_batch_id uuid
  REFERENCES public.bulk_assign_batches(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS plan_workout_releases_bulk_batch
  ON public.plan_workout_releases (bulk_batch_id)
  WHERE bulk_batch_id IS NOT NULL;

ALTER TABLE public.training_plan_weeks
  ADD COLUMN IF NOT EXISTS bulk_batch_id uuid
  REFERENCES public.bulk_assign_batches(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS training_plan_weeks_bulk_batch
  ON public.training_plan_weeks (bulk_batch_id)
  WHERE bulk_batch_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 2. RLS
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.bulk_assign_batches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bulk_assign_batches_staff_read ON public.bulk_assign_batches;
CREATE POLICY bulk_assign_batches_staff_read
  ON public.bulk_assign_batches
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = bulk_assign_batches.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- DML só via SECURITY DEFINER RPCs.
DROP POLICY IF EXISTS bulk_assign_batches_no_direct_dml ON public.bulk_assign_batches;
CREATE POLICY bulk_assign_batches_no_direct_dml
  ON public.bulk_assign_batches
  FOR ALL
  USING (false)
  WITH CHECK (false);

-- ─────────────────────────────────────────────────────────────────────
-- 3. RPCs
-- ─────────────────────────────────────────────────────────────────────

-- 3.1 Abrir batch.
CREATE OR REPLACE FUNCTION public.fn_bulk_assign_batch_open(
  p_group_id        uuid,
  p_actor_id        uuid,
  p_description     text,
  p_ttl_minutes     int DEFAULT 60
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role    text;
  v_ttl     int;
  v_id      uuid;
BEGIN
  IF p_group_id IS NULL OR p_actor_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'INVALID_INPUT',
      DETAIL  = 'L23-04: p_group_id and p_actor_id required';
  END IF;

  v_ttl := COALESCE(p_ttl_minutes, 60);
  IF v_ttl < 1 OR v_ttl > 1440 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'INVALID_INPUT',
      DETAIL  = format('L23-04: ttl_minutes %s outside [1,1440]', v_ttl);
  END IF;

  SELECT role INTO v_role
  FROM public.coaching_members
  WHERE group_id = p_group_id AND user_id = p_actor_id
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master', 'coach') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'UNAUTHORIZED',
      DETAIL  = 'L23-04: only admin_master or coach may open a bulk-assign batch';
  END IF;

  INSERT INTO public.bulk_assign_batches (
    group_id, actor_id, description, undo_ttl_minutes
  ) VALUES (
    p_group_id, p_actor_id, p_description, v_ttl
  ) RETURNING id INTO v_id;

  RETURN v_id;
END
$$;

-- 3.2 Anexar releases/weeks a um batch.
CREATE OR REPLACE FUNCTION public.fn_bulk_assign_batch_attach(
  p_batch_id    uuid,
  p_release_ids uuid[],
  p_week_ids    uuid[] DEFAULT ARRAY[]::uuid[]
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch      public.bulk_assign_batches%ROWTYPE;
  v_release_n  int := 0;
  v_week_n     int := 0;
BEGIN
  IF p_batch_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'INVALID_INPUT',
      DETAIL  = 'L23-04: p_batch_id required';
  END IF;

  SELECT * INTO v_batch
  FROM public.bulk_assign_batches
  WHERE id = p_batch_id
  FOR UPDATE;

  IF v_batch.id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0002',
      MESSAGE = 'BATCH_NOT_FOUND',
      DETAIL  = format('L23-04: batch %s does not exist', p_batch_id);
  END IF;

  IF v_batch.undone_at IS NOT NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0003',
      MESSAGE = 'BATCH_ALREADY_UNDONE',
      DETAIL  = 'L23-04: cannot attach to an already-undone batch';
  END IF;

  -- Attach releases — only within the batch's group (defense in depth).
  IF p_release_ids IS NOT NULL AND array_length(p_release_ids, 1) > 0 THEN
    WITH u AS (
      UPDATE public.plan_workout_releases
      SET bulk_batch_id = p_batch_id
      WHERE id = ANY(p_release_ids)
        AND group_id = v_batch.group_id
        AND bulk_batch_id IS NULL
      RETURNING 1
    )
    SELECT COUNT(*) INTO v_release_n FROM u;
  END IF;

  IF p_week_ids IS NOT NULL AND array_length(p_week_ids, 1) > 0 THEN
    WITH u AS (
      UPDATE public.training_plan_weeks w
      SET bulk_batch_id = p_batch_id
      FROM public.training_plans p
      WHERE w.id = ANY(p_week_ids)
        AND w.plan_id = p.id
        AND p.group_id = v_batch.group_id
        AND w.bulk_batch_id IS NULL
      RETURNING 1
    )
    SELECT COUNT(*) INTO v_week_n FROM u;
  END IF;

  UPDATE public.bulk_assign_batches
  SET items_count = items_count + v_release_n + v_week_n
  WHERE id = p_batch_id;

  RETURN v_release_n + v_week_n;
END
$$;

-- 3.3 Desfazer batch.
CREATE OR REPLACE FUNCTION public.fn_bulk_assign_batch_undo(
  p_batch_id  uuid,
  p_actor_id  uuid,
  p_reason    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch     public.bulk_assign_batches%ROWTYPE;
  v_role      text;
  v_is_admin  boolean := false;
  v_now       timestamptz := now();
  v_cut       timestamptz;
  v_releases  int := 0;
  v_weeks     int := 0;
BEGIN
  IF p_batch_id IS NULL OR p_actor_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'INVALID_INPUT',
      DETAIL  = 'L23-04: p_batch_id and p_actor_id required';
  END IF;

  SELECT * INTO v_batch
  FROM public.bulk_assign_batches
  WHERE id = p_batch_id
  FOR UPDATE;

  IF v_batch.id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0002',
      MESSAGE = 'BATCH_NOT_FOUND',
      DETAIL  = format('L23-04: batch %s does not exist', p_batch_id);
  END IF;

  IF v_batch.undone_at IS NOT NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0003',
      MESSAGE = 'BATCH_ALREADY_UNDONE',
      DETAIL  = format(
        'L23-04: batch %s already undone at %s',
        p_batch_id, v_batch.undone_at
      );
  END IF;

  -- TTL gate.
  v_cut := v_batch.created_at
         + make_interval(mins => v_batch.undo_ttl_minutes);
  IF v_now > v_cut THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0005',
      MESSAGE = 'UNDO_WINDOW_EXPIRED',
      DETAIL  = format(
        'L23-04: undo window closed at %s (now %s)', v_cut, v_now
      );
  END IF;

  -- Role gate — must be coach/admin_master OR platform_admin.
  SELECT role INTO v_role
  FROM public.coaching_members
  WHERE group_id = v_batch.group_id AND user_id = p_actor_id
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master', 'coach') THEN
    -- Check platform_admin fallback.
    SELECT EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.user_id = p_actor_id
    ) INTO v_is_admin;
    IF NOT v_is_admin THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0010',
        MESSAGE = 'UNAUTHORIZED',
        DETAIL  = 'L23-04: actor is not coach/admin_master of group nor platform_admin';
    END IF;
  END IF;

  -- Author gate — only original actor (or platform_admin) may undo.
  IF p_actor_id <> v_batch.actor_id AND NOT v_is_admin THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'UNAUTHORIZED',
      DETAIL  = 'L23-04: only the original author or a platform_admin may undo this batch';
  END IF;

  -- Cancel releases belonging to this batch.
  WITH u AS (
    UPDATE public.plan_workout_releases
    SET release_status = 'cancelled',
        updated_by     = p_actor_id
    WHERE bulk_batch_id = p_batch_id
      AND release_status NOT IN ('cancelled', 'replaced', 'archived')
    RETURNING id
  )
  SELECT COUNT(*) INTO v_releases FROM u;

  -- Mark affected weeks as cancelled.
  WITH u AS (
    UPDATE public.training_plan_weeks
    SET status = 'cancelled',
        updated_at = v_now
    WHERE bulk_batch_id = p_batch_id
      AND status <> 'cancelled'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_weeks FROM u;

  -- Audit trail via workout_change_log.
  INSERT INTO public.workout_change_log (
    release_id, group_id, changed_by, change_type, new_value
  )
  SELECT r.id, r.group_id, p_actor_id,
         'bulk_assign_undone',
         jsonb_build_object(
           'batch_id',  p_batch_id,
           'reason',    p_reason,
           'undone_at', v_now
         )
  FROM public.plan_workout_releases r
  WHERE r.bulk_batch_id = p_batch_id;

  UPDATE public.bulk_assign_batches
  SET undone_at   = v_now,
      undone_by   = p_actor_id,
      undo_reason = p_reason
  WHERE id = p_batch_id;

  RETURN jsonb_build_object(
    'batch_id',         p_batch_id,
    'undone_at',        v_now,
    'releases_undone',  v_releases,
    'weeks_undone',     v_weeks,
    'reason',           p_reason
  );
END
$$;

-- 3.4 Status summary (pode desfazer?).
CREATE OR REPLACE FUNCTION public.fn_bulk_assign_batch_summary(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_batch  public.bulk_assign_batches%ROWTYPE;
  v_caller uuid := auth.uid();
  v_role   text;
  v_cut    timestamptz;
BEGIN
  SELECT * INTO v_batch
  FROM public.bulk_assign_batches
  WHERE id = p_batch_id;

  IF v_batch.id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0002',
      MESSAGE = 'BATCH_NOT_FOUND';
  END IF;

  SELECT role INTO v_role
  FROM public.coaching_members
  WHERE group_id = v_batch.group_id AND user_id = v_caller
  LIMIT 1;

  IF v_role IS NULL
     OR v_role NOT IN ('admin_master', 'coach', 'assistant') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'UNAUTHORIZED';
  END IF;

  v_cut := v_batch.created_at
         + make_interval(mins => v_batch.undo_ttl_minutes);

  RETURN jsonb_build_object(
    'batch_id',         v_batch.id,
    'group_id',         v_batch.group_id,
    'actor_id',         v_batch.actor_id,
    'description',      v_batch.description,
    'items_count',      v_batch.items_count,
    'created_at',       v_batch.created_at,
    'undo_ttl_minutes', v_batch.undo_ttl_minutes,
    'undo_deadline',    v_cut,
    'can_undo',         (
      v_batch.undone_at IS NULL
      AND now() <= v_cut
      AND (v_caller = v_batch.actor_id)
    ),
    'already_undone',   (v_batch.undone_at IS NOT NULL),
    'undone_at',        v_batch.undone_at,
    'undone_by',        v_batch.undone_by,
    'undo_reason',      v_batch.undo_reason
  );
END
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Grants
-- ─────────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.fn_bulk_assign_batch_open(uuid, uuid, text, int)            FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_bulk_assign_batch_attach(uuid, uuid[], uuid[])           FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_bulk_assign_batch_undo(uuid, uuid, text)                 FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_bulk_assign_batch_summary(uuid)                          FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_bulk_assign_batch_open(uuid, uuid, text, int)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_bulk_assign_batch_attach(uuid, uuid[], uuid[])           TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_bulk_assign_batch_undo(uuid, uuid, text)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_bulk_assign_batch_summary(uuid)                          TO authenticated;

COMMENT ON FUNCTION public.fn_bulk_assign_batch_undo(uuid, uuid, text) IS
  'L23-04: atomic undo of a bulk-assign batch within TTL (default 60 min). '
  'Cancels plan_workout_releases and training_plan_weeks whose bulk_batch_id '
  'matches. Author-or-platform-admin gate. Never touches coin_ledger. L04-07-OK.';

-- ─────────────────────────────────────────────────────────────────────
-- 5. Self-test
-- ─────────────────────────────────────────────────────────────────────

DO $test$
DECLARE
  v_ok boolean;
BEGIN
  -- 5.1 Table created.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='bulk_assign_batches'
  ) THEN
    RAISE EXCEPTION 'L23-04 self-test: bulk_assign_batches table missing';
  END IF;

  -- 5.2 bulk_batch_id columns added.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='plan_workout_releases'
      AND column_name='bulk_batch_id'
  ) THEN
    RAISE EXCEPTION 'L23-04 self-test: plan_workout_releases.bulk_batch_id missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='training_plan_weeks'
      AND column_name='bulk_batch_id'
  ) THEN
    RAISE EXCEPTION 'L23-04 self-test: training_plan_weeks.bulk_batch_id missing';
  END IF;

  -- 5.3 All four functions registered as SECURITY DEFINER.
  SELECT bool_and(prosecdef) INTO v_ok
  FROM pg_proc
  WHERE proname IN (
    'fn_bulk_assign_batch_open',
    'fn_bulk_assign_batch_attach',
    'fn_bulk_assign_batch_undo',
    'fn_bulk_assign_batch_summary'
  );
  IF NOT COALESCE(v_ok, false) THEN
    RAISE EXCEPTION 'L23-04 self-test: at least one RPC missing or not SECURITY DEFINER';
  END IF;

  -- 5.4 RLS enabled.
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public' AND c.relname='bulk_assign_batches' AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'L23-04 self-test: RLS disabled on bulk_assign_batches';
  END IF;

  RAISE NOTICE 'L23-04 self-test PASSED';
END
$test$;

COMMIT;
