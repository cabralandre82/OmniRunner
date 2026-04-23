-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ L23-01 — fn_bulk_assign_preview                                          ║
-- ║                                                                           ║
-- ║ Gera matriz de risco "atleta × alerta" ANTES de um bulk-assign ser       ║
-- ║ gravado, permitindo ao coach revisar a distribuição e ajustar            ║
-- ║ individualmente antes de publicar.                                        ║
-- ║                                                                           ║
-- ║ Finding : docs/audit/findings/L23-01-workout-delivery-em-massa-sem-      ║
-- ║           preview-por-atleta.md                                           ║
-- ║                                                                           ║
-- ║ Contract                                                                  ║
-- ║ --------                                                                  ║
-- ║ RPC `public.fn_bulk_assign_preview(p_group_id uuid,                      ║
-- ║                                    p_athlete_ids uuid[],                 ║
-- ║                                    p_target_date date,                   ║
-- ║                                    p_planned_tss numeric DEFAULT NULL)`  ║
-- ║   • SECURITY DEFINER, STABLE (read-only; no writes to any table).        ║
-- ║   • Caller MUST be coach/assistant of the group (role gate).             ║
-- ║   • Input  : up to 500 athlete UUIDs (DoS guard).                        ║
-- ║   • Output : jsonb envelope with summary counts and per-athlete row.    ║
-- ║                                                                           ║
-- ║ Risk levels                                                               ║
-- ║ -----------                                                               ║
-- ║   red   — workouts confirmed in last 7 days ≥ 7  OR                      ║
-- ║           upcoming (pending/published) assignments this week ≥ 5         ║
-- ║   yellow— workouts confirmed in last 7 days ≥ 5  OR                      ║
-- ║           upcoming assignments this week ≥ 3                             ║
-- ║   gray  — 0 confirmed workouts in last 14 days                           ║
-- ║   green — none of the above                                              ║
-- ║                                                                           ║
-- ║ Errors                                                                    ║
-- ║ ------                                                                    ║
-- ║   P0010 UNAUTHORIZED     — caller is not coach/assistant of group.       ║
-- ║   P0001 INVALID_INPUT    — empty or oversized p_athlete_ids.             ║
-- ║   P0002 GROUP_NOT_FOUND  — p_group_id does not exist.                    ║
-- ║                                                                           ║
-- ║ OmniCoin policy                                                           ║
-- ║ ---------------                                                           ║
-- ║ Read-only; never touches public.coin_ledger / public.wallets.            ║
-- ║ L04-07-OK                                                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. RPC
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_bulk_assign_preview(
  p_group_id    uuid,
  p_athlete_ids uuid[],
  p_target_date date DEFAULT CURRENT_DATE,
  p_planned_tss numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_caller        uuid := auth.uid();
  v_role          text;
  v_input_count   int;
  v_rows          jsonb;
  v_green         int := 0;
  v_yellow        int := 0;
  v_red           int := 0;
  v_gray          int := 0;
  v_group_exists  boolean;
BEGIN
  -- 1.1 — basic input shape
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'INVALID_INPUT',
      DETAIL  = 'L23-01: p_group_id must not be null';
  END IF;

  v_input_count := COALESCE(array_length(p_athlete_ids, 1), 0);
  IF v_input_count = 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'INVALID_INPUT',
      DETAIL  = 'L23-01: p_athlete_ids must be a non-empty array';
  END IF;
  IF v_input_count > 500 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'INVALID_INPUT',
      DETAIL  = format('L23-01: p_athlete_ids size %s exceeds cap 500', v_input_count);
  END IF;

  -- 1.2 — group existence gate
  SELECT EXISTS(SELECT 1 FROM public.coaching_groups WHERE id = p_group_id)
    INTO v_group_exists;
  IF NOT v_group_exists THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0002',
      MESSAGE = 'GROUP_NOT_FOUND',
      DETAIL  = format('L23-01: group %s does not exist', p_group_id);
  END IF;

  -- 1.3 — coach/assistant role gate
  IF v_caller IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'UNAUTHORIZED',
      DETAIL  = 'L23-01: no auth.uid() resolved';
  END IF;

  SELECT cm.role INTO v_role
  FROM public.coaching_members cm
  WHERE cm.group_id = p_group_id
    AND cm.user_id  = v_caller
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('coach', 'assistant') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'UNAUTHORIZED',
      DETAIL  = 'L23-01: caller is not coach/assistant of the group';
  END IF;

  -- 1.4 — derive risk per athlete.
  WITH
    input AS (
      SELECT unnest(p_athlete_ids) AS athlete_id
    ),
    membership AS (
      SELECT i.athlete_id, cm.display_name, cm.role AS member_role
      FROM input i
      LEFT JOIN public.coaching_members cm
        ON cm.group_id = p_group_id
       AND cm.user_id  = i.athlete_id
    ),
    confirmed_7d AS (
      SELECT di.athlete_user_id,
             COUNT(*) AS n,
             MAX(di.confirmed_at) AS last_confirmed_at
      FROM public.workout_delivery_items di
      WHERE di.group_id = p_group_id
        AND di.athlete_user_id = ANY(p_athlete_ids)
        AND di.status = 'confirmed'
        AND di.confirmed_at >= now() - INTERVAL '7 days'
      GROUP BY di.athlete_user_id
    ),
    confirmed_14d AS (
      SELECT di.athlete_user_id, COUNT(*) AS n
      FROM public.workout_delivery_items di
      WHERE di.group_id = p_group_id
        AND di.athlete_user_id = ANY(p_athlete_ids)
        AND di.status = 'confirmed'
        AND di.confirmed_at >= now() - INTERVAL '14 days'
      GROUP BY di.athlete_user_id
    ),
    upcoming AS (
      SELECT di.athlete_user_id, COUNT(*) AS n
      FROM public.workout_delivery_items di
      WHERE di.group_id = p_group_id
        AND di.athlete_user_id = ANY(p_athlete_ids)
        AND di.status IN ('pending', 'published')
        AND di.created_at >= date_trunc('week', now())
      GROUP BY di.athlete_user_id
    ),
    classified AS (
      SELECT
        m.athlete_id,
        m.display_name,
        m.member_role,
        COALESCE(c7.n,  0) AS confirmed_7d,
        COALESCE(c14.n, 0) AS confirmed_14d,
        COALESCE(u.n,   0) AS upcoming_count,
        c7.last_confirmed_at,
        CASE
          WHEN m.member_role IS NULL OR m.member_role <> 'athlete' THEN 'gray'
          WHEN COALESCE(c14.n, 0) = 0 THEN 'gray'
          WHEN COALESCE(c7.n, 0) >= 7 OR COALESCE(u.n, 0) >= 5 THEN 'red'
          WHEN COALESCE(c7.n, 0) >= 5 OR COALESCE(u.n, 0) >= 3 THEN 'yellow'
          ELSE 'green'
        END AS risk_level,
        CASE
          WHEN m.member_role IS NULL OR m.member_role <> 'athlete' THEN
            jsonb_build_array('not_in_group_as_athlete')
          WHEN COALESCE(c14.n, 0) = 0 THEN
            jsonb_build_array('no_baseline_14d')
          ELSE (
            SELECT coalesce(jsonb_agg(reason), '[]'::jsonb)
            FROM (
              SELECT 'workload_7d:' || COALESCE(c7.n, 0) AS reason
              WHERE COALESCE(c7.n, 0) >= 5
              UNION ALL
              SELECT 'upcoming_week:' || COALESCE(u.n, 0)
              WHERE COALESCE(u.n, 0) >= 3
            ) s
          )
        END AS reasons
      FROM membership m
      LEFT JOIN confirmed_7d  c7  ON c7.athlete_user_id  = m.athlete_id
      LEFT JOIN confirmed_14d c14 ON c14.athlete_user_id = m.athlete_id
      LEFT JOIN upcoming      u   ON u.athlete_user_id   = m.athlete_id
    )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'athlete_id',          c.athlete_id,
      'display_name',        c.display_name,
      'is_member',           (c.member_role IS NOT NULL),
      'member_role',         c.member_role,
      'risk_level',          c.risk_level,
      'reasons',             coalesce(c.reasons, '[]'::jsonb),
      'workouts_confirmed_7d',  c.confirmed_7d,
      'workouts_confirmed_14d', c.confirmed_14d,
      'upcoming_week_count',    c.upcoming_count,
      'last_confirmed_at',      c.last_confirmed_at
    ) ORDER BY
      -- Sort red first, then yellow, gray, green — safer-first UX.
      CASE c.risk_level
        WHEN 'red' THEN 0 WHEN 'yellow' THEN 1
        WHEN 'gray' THEN 2 ELSE 3
      END,
      c.display_name NULLS LAST
    ),'[]'::jsonb),
    SUM(CASE WHEN c.risk_level = 'green'  THEN 1 ELSE 0 END)::int,
    SUM(CASE WHEN c.risk_level = 'yellow' THEN 1 ELSE 0 END)::int,
    SUM(CASE WHEN c.risk_level = 'red'    THEN 1 ELSE 0 END)::int,
    SUM(CASE WHEN c.risk_level = 'gray'   THEN 1 ELSE 0 END)::int
  INTO v_rows, v_green, v_yellow, v_red, v_gray
  FROM classified c;

  RETURN jsonb_build_object(
    'generated_at',  now(),
    'group_id',      p_group_id,
    'target_date',   p_target_date,
    'planned_tss',   p_planned_tss,
    'input_count',   v_input_count,
    'counts', jsonb_build_object(
      'green',  COALESCE(v_green,  0),
      'yellow', COALESCE(v_yellow, 0),
      'red',    COALESCE(v_red,    0),
      'gray',   COALESCE(v_gray,   0)
    ),
    'athletes',      COALESCE(v_rows, '[]'::jsonb)
  );
END
$$;

COMMENT ON FUNCTION public.fn_bulk_assign_preview(uuid, uuid[], date, numeric) IS
  'L23-01: read-only risk-preview RPC for bulk workout assignment. '
  'Caller MUST be coach/assistant (P0010 otherwise). Returns jsonb '
  'with risk_level per athlete (red/yellow/gray/green) derived from '
  'confirmed_7d, confirmed_14d and upcoming_week workloads. Never '
  'touches coin_ledger. L04-07-OK.';

REVOKE ALL ON FUNCTION public.fn_bulk_assign_preview(uuid, uuid[], date, numeric)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_bulk_assign_preview(uuid, uuid[], date, numeric)
  TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Self-test — schema invariants
-- ─────────────────────────────────────────────────────────────────────

DO $test$
DECLARE
  v_is_sd   boolean;
  v_vola    char;
  v_arg_cnt int;
BEGIN
  -- 2.1 Function exists with 4 args.
  SELECT p.prosecdef, p.provolatile, p.pronargs
    INTO v_is_sd, v_vola, v_arg_cnt
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname  = 'fn_bulk_assign_preview'
  LIMIT 1;

  IF v_is_sd IS NULL THEN
    RAISE EXCEPTION 'L23-01 self-test: fn_bulk_assign_preview not registered';
  END IF;
  IF NOT v_is_sd THEN
    RAISE EXCEPTION 'L23-01 self-test: fn_bulk_assign_preview must be SECURITY DEFINER';
  END IF;
  IF v_vola <> 's' THEN
    RAISE EXCEPTION 'L23-01 self-test: fn_bulk_assign_preview must be STABLE (got %)', v_vola;
  END IF;
  IF v_arg_cnt <> 4 THEN
    RAISE EXCEPTION 'L23-01 self-test: fn_bulk_assign_preview must have 4 args (got %)', v_arg_cnt;
  END IF;

  -- 2.2 Authenticated grant must exist.
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public'
      AND routine_name   = 'fn_bulk_assign_preview'
      AND grantee        = 'authenticated'
      AND privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'L23-01 self-test: EXECUTE grant missing for authenticated';
  END IF;

  RAISE NOTICE 'L23-01 self-test PASSED';
END
$test$;

COMMIT;
