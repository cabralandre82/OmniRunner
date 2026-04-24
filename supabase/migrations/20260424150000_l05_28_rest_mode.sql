-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L05-28 — rest_mode semantics (stand_still / walk / jog)                    ║
-- ║                                                                            ║
-- ║ Problem:                                                                   ║
-- ║   Coaches describe "pausa" with three real-world meanings that collapse   ║
-- ║   into two block types today:                                              ║
-- ║     * "parado"     → block_type='rest'     (ambiguous today)              ║
-- ║     * "caminhando" → block_type='rest' OR 'recovery' (coach's guess)      ║
-- ║     * "trote leve" → block_type='recovery' (ambiguous today)              ║
-- ║   The athlete receives a generic "REST" or "RECOVERY" label on the watch  ║
-- ║   and does not know whether to stop, walk, or jog. This lives outside    ║
-- ║   FIT's intensity taxonomy (no physical detection between stand/walk);   ║
-- ║   it's a semantic layer that must be carried as metadata for the UI,    ║
-- ║   the AI copilot, and any future analysis that reasons about HR drift.   ║
-- ║                                                                            ║
-- ║ Fix:                                                                       ║
-- ║   1. Add nullable `rest_mode` column with values {stand_still, walk, jog}.║
-- ║   2. CHECK that rest_mode IS NULL unless block_type IN ('rest','recovery')║
-- ║   3. CHECK that block_type='rest' + rest_mode='jog' is rejected at        ║
-- ║      definition level (if the coach wants a jog, they use 'recovery';   ║
-- ║      'rest' inherently means NOT jogging).                                ║
-- ║   4. Comment on columns with rationale + allowed combinations so DB     ║
-- ║      readers don't have to dig through audit docs to understand.        ║
-- ║                                                                            ║
-- ║ Backward-compat:                                                           ║
-- ║   * All existing rows keep rest_mode=NULL (legacy behavior preserved).   ║
-- ║   * FIT encoder unchanged — intensity still derived from block_type only.║
-- ║     rest_mode is purely metadata for rendering and downstream analysis.  ║
-- ║   * Zod schemas + AI parser updated in companion PR (portal/*).          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. Add column ───────────────────────────────────────────────────────────

ALTER TABLE public.coaching_workout_blocks
  ADD COLUMN IF NOT EXISTS rest_mode text;

-- ─── 2. Enum CHECK ───────────────────────────────────────────────────────────

DO $$ BEGIN
  ALTER TABLE public.coaching_workout_blocks
    DROP CONSTRAINT IF EXISTS coaching_workout_blocks_rest_mode_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT coaching_workout_blocks_rest_mode_check
  CHECK (rest_mode IS NULL OR rest_mode IN ('stand_still', 'walk', 'jog'));

-- ─── 3. Scope CHECK: rest_mode only for rest/recovery ────────────────────────

DO $$ BEGIN
  ALTER TABLE public.coaching_workout_blocks
    DROP CONSTRAINT IF EXISTS coaching_workout_blocks_rest_mode_scope;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT coaching_workout_blocks_rest_mode_scope
  CHECK (
    rest_mode IS NULL
    OR block_type IN ('rest', 'recovery')
  );

-- ─── 4. Definition CHECK: jog only valid inside 'recovery' ────────────────────

-- Rationale: 'rest' by definition means NOT jogging. A coach who wants the
-- athlete to keep moving actively uses 'recovery'. Rejecting rest+jog at the
-- DB prevents the UI from drifting into an inconsistent three-way combinatorial
-- state and keeps the mapping rest_mode → watch intensity unambiguous:
--   stand_still → REST    (watch pauses distance/pace)
--   walk        → REST/RECOVERY (no physical detection either way)
--   jog         → RECOVERY (watch keeps recording movement)

DO $$ BEGIN
  ALTER TABLE public.coaching_workout_blocks
    DROP CONSTRAINT IF EXISTS coaching_workout_blocks_rest_mode_jog_only_recovery;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT coaching_workout_blocks_rest_mode_jog_only_recovery
  CHECK (
    rest_mode <> 'jog'
    OR block_type = 'recovery'
  );

-- ─── 5. Column comment ───────────────────────────────────────────────────────

COMMENT ON COLUMN public.coaching_workout_blocks.rest_mode IS
  'Semantic sub-mode for rest/recovery blocks. '
  'stand_still: athlete stops entirely (drink water, catch breath). '
  'walk: athlete walks actively between efforts. '
  'jog: athlete jogs lightly (only valid with block_type=recovery). '
  'NULL on any block_type NOT IN (rest, recovery). '
  'NULL on rest/recovery = legacy/unspecified (UI falls back to generic label). '
  'See docs/audit/findings/L05-28-rest-mode-semantica-ausente.md.';

-- ─── 6. Sanity self-check: no existing row violates the new constraints ──────

DO $selfcheck$
DECLARE
  v_bad_scope INT;
  v_bad_jog INT;
  v_bad_enum INT;
BEGIN
  SELECT count(*) INTO v_bad_scope
    FROM public.coaching_workout_blocks
   WHERE rest_mode IS NOT NULL
     AND block_type NOT IN ('rest', 'recovery');

  SELECT count(*) INTO v_bad_jog
    FROM public.coaching_workout_blocks
   WHERE rest_mode = 'jog'
     AND block_type <> 'recovery';

  SELECT count(*) INTO v_bad_enum
    FROM public.coaching_workout_blocks
   WHERE rest_mode IS NOT NULL
     AND rest_mode NOT IN ('stand_still', 'walk', 'jog');

  IF v_bad_scope > 0 OR v_bad_jog > 0 OR v_bad_enum > 0 THEN
    RAISE EXCEPTION
      'L05-28 self-check failed: % scope violations, % jog violations, % enum violations. '
      'This should be impossible on a fresh deploy (column just added NULL). '
      'Aborting migration.',
      v_bad_scope, v_bad_jog, v_bad_enum;
  END IF;
END;
$selfcheck$;

COMMIT;
