-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L05-21 — Workout repeat terminator                                         ║
-- ║                                                                            ║
-- ║ Problem:                                                                   ║
-- ║   coaching_workout_blocks models repetitions as a flat list with a        ║
-- ║   'repeat' marker block (carrying repeat_count). There is NO terminator   ║
-- ║   to close the repeat group. Four independent call-sites inferred the    ║
-- ║   end with inconsistent heuristics:                                       ║
-- ║     * Portal UI: "repeat stays open while next block ∈ {interval,         ║
-- ║       recovery}" — implicit, no guarantee.                                ║
-- ║     * Edge Function generate-fit-workout: "repeat collects blocks until  ║
-- ║       the NEXT 'repeat' or end-of-list" — different rule.                 ║
-- ║   Consequence on a typical [warmup, repeat(5), int, rec, cooldown]:       ║
-- ║     * Portal shows: warmup → 5×(int+rec) → cooldown. Total 5km interval.  ║
-- ║     * Watch receives: warmup → 5×(int+rec+cooldown) → END. 55km loop.     ║
-- ║   → Coach trust destroyed on first real intervalado workout pushed.       ║
-- ║                                                                            ║
-- ║ Fix:                                                                       ║
-- ║   1. Extend block_type CHECK to accept 'repeat_end'.                      ║
-- ║   2. Backfill existing templates: walk blocks; when a 'repeat' is open   ║
-- ║      and we hit a block NOT IN ('interval','recovery'), insert a         ║
-- ║      'repeat_end' marker right before it (preserves what the coach saw   ║
-- ║      in the portal UI = ground truth of intent).                          ║
-- ║   3. Trigger `trg_block_repeat_balance` — on INSERT/UPDATE/DELETE,        ║
-- ║      guarantee per-template: count('repeat') == count('repeat_end')       ║
-- ║      AND every 'repeat_end' is preceded by a matching 'repeat' at a       ║
-- ║      lower order_index with no unclosed inner 'repeat' in between.        ║
-- ║      Rejects unbalanced insert with a clear SQLSTATE 23514.               ║
-- ║   4. (out of scope here) portal UI, Zod schemas, AI parser, edge FIT      ║
-- ║      encoder are updated in companion PR — see L05-22 and L05-23.         ║
-- ║                                                                            ║
-- ║ Safety:                                                                    ║
-- ║   * Idempotent: the backfill DO block only runs if 'repeat_end' is not    ║
-- ║     yet present in any block of any template containing a 'repeat'.      ║
-- ║   * Does NOT touch content_snapshot of plan_workout_releases (those are   ║
-- ║     historical and immutable by design). Older releases will remain      ║
-- ║     with the flat format; the edge encoder keeps backward-compat for     ║
-- ║     snapshots without repeat_end (legacy fallback = "until next repeat   ║
-- ║     or end-of-list", consistent with pre-L05-21 behavior).                ║
-- ║   * order_index gaps created by inserts remain (sparse but strictly       ║
-- ║     increasing) — no consumer requires density.                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. Extend block_type CHECK constraint ────────────────────────────────────

DO $$ BEGIN
  ALTER TABLE public.coaching_workout_blocks
    DROP CONSTRAINT IF EXISTS coaching_workout_blocks_block_type_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT coaching_workout_blocks_block_type_check
  CHECK (block_type IN (
    'warmup', 'interval', 'recovery', 'cooldown',
    'steady', 'rest', 'repeat', 'repeat_end'
  ));

COMMENT ON COLUMN public.coaching_workout_blocks.block_type IS
  'warmup|interval|recovery|cooldown|steady|rest: execution blocks. '
  'repeat: opens a group with repeat_count≥2, inner blocks follow. '
  'repeat_end: closes the nearest open repeat group (required when the '
  'next block is NOT interval|recovery, to avoid ambiguity in the FIT '
  'encoder). See docs/audit/findings/L05-21-*.md.';

-- ─── 2. Backfill: insert 'repeat_end' into legacy templates ───────────────────

DO $backfill$
DECLARE
  v_template_id UUID;
  v_block RECORD;
  v_in_repeat BOOLEAN;
  v_insert_at INT;
  v_next_order INT;
  v_inserted INT := 0;
BEGIN
  -- Only run if the catalog has no repeat_end markers yet (idempotent guard)
  IF EXISTS (
    SELECT 1 FROM public.coaching_workout_blocks WHERE block_type = 'repeat_end'
  ) THEN
    RAISE NOTICE 'Backfill skipped: repeat_end markers already present.';
    RETURN;
  END IF;

  FOR v_template_id IN
    SELECT DISTINCT template_id
      FROM public.coaching_workout_blocks
     WHERE block_type = 'repeat'
  LOOP
    v_in_repeat := FALSE;
    v_insert_at := NULL;

    FOR v_block IN
      SELECT id, order_index, block_type
        FROM public.coaching_workout_blocks
       WHERE template_id = v_template_id
       ORDER BY order_index ASC
    LOOP
      IF v_block.block_type = 'repeat' THEN
        -- New repeat opens; if one was already open (coach double-stacked
        -- without terminator) close it here before this block.
        IF v_in_repeat THEN
          v_next_order := v_block.order_index;
          INSERT INTO public.coaching_workout_blocks
            (template_id, order_index, block_type)
          VALUES
            (v_template_id, v_next_order - 1, 'repeat_end');
          v_inserted := v_inserted + 1;
        END IF;
        v_in_repeat := TRUE;
      ELSIF v_in_repeat AND v_block.block_type NOT IN ('interval', 'recovery') THEN
        -- Close the repeat group right before this non-active block.
        INSERT INTO public.coaching_workout_blocks
          (template_id, order_index, block_type)
        VALUES
          (v_template_id, v_block.order_index - 1, 'repeat_end');
        v_inserted := v_inserted + 1;
        v_in_repeat := FALSE;
      END IF;
    END LOOP;

    -- Tail case: repeat group reaches end of template without explicit closer.
    IF v_in_repeat THEN
      SELECT COALESCE(MAX(order_index), 0) + 1
        INTO v_next_order
        FROM public.coaching_workout_blocks
       WHERE template_id = v_template_id;

      INSERT INTO public.coaching_workout_blocks
        (template_id, order_index, block_type)
      VALUES
        (v_template_id, v_next_order, 'repeat_end');
      v_inserted := v_inserted + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'Backfill complete: % repeat_end markers inserted.', v_inserted;
END;
$backfill$;

-- ─── 3. Balance trigger: enforce repeat/repeat_end integrity per template ─────

CREATE OR REPLACE FUNCTION public.fn_validate_workout_block_balance(
  p_template_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_block RECORD;
  v_depth INT := 0;
BEGIN
  FOR v_block IN
    SELECT block_type, order_index
      FROM public.coaching_workout_blocks
     WHERE template_id = p_template_id
     ORDER BY order_index ASC
  LOOP
    IF v_block.block_type = 'repeat' THEN
      v_depth := v_depth + 1;
      -- We currently only support ONE level of nesting (flat repeats).
      -- Nested repeats would need DUR_REPEAT_UNTIL_STEPS_CMPLT back-references
      -- that we do NOT emit correctly today. Reject until L05-21+1 adds it.
      IF v_depth > 1 THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'workout_block_nested_repeat_unsupported',
          DETAIL  = format(
            'Template %s has a nested repeat at order_index %s. '
            'Nested repeats are not supported by the FIT encoder. '
            'Close the outer repeat with repeat_end before opening another.',
            p_template_id, v_block.order_index
          );
      END IF;
    ELSIF v_block.block_type = 'repeat_end' THEN
      IF v_depth = 0 THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'workout_block_orphan_repeat_end',
          DETAIL  = format(
            'Template %s has a repeat_end at order_index %s '
            'with no matching repeat opener before it.',
            p_template_id, v_block.order_index
          );
      END IF;
      v_depth := v_depth - 1;
    END IF;
  END LOOP;

  IF v_depth <> 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'workout_block_unbalanced_repeats',
      DETAIL  = format(
        'Template %s has %s unclosed repeat group(s). '
        'Every repeat must be followed by a repeat_end at the same nesting level.',
        p_template_id, v_depth
      );
  END IF;
END;
$fn$;

COMMENT ON FUNCTION public.fn_validate_workout_block_balance(UUID) IS
  'Raises 23514 if the template has unbalanced repeat/repeat_end markers '
  'or nested repeats. Called by trg_block_repeat_balance on I/U/D.';

CREATE OR REPLACE FUNCTION public.trg_fn_workout_block_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $trg$
DECLARE
  v_template_id UUID;
BEGIN
  -- Resolve the affected template id (works for INSERT/UPDATE/DELETE).
  v_template_id := COALESCE(NEW.template_id, OLD.template_id);

  -- Only validate when the change could plausibly affect balance:
  -- any change to block_type, or an insert/delete of repeat/repeat_end rows.
  IF (TG_OP = 'INSERT' AND NEW.block_type IN ('repeat', 'repeat_end'))
     OR (TG_OP = 'DELETE' AND OLD.block_type IN ('repeat', 'repeat_end'))
     OR (TG_OP = 'UPDATE' AND (
           NEW.block_type IS DISTINCT FROM OLD.block_type
           OR NEW.order_index IS DISTINCT FROM OLD.order_index
         ))
  THEN
    PERFORM public.fn_validate_workout_block_balance(v_template_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$trg$;

DROP TRIGGER IF EXISTS trg_block_repeat_balance
  ON public.coaching_workout_blocks;

CREATE CONSTRAINT TRIGGER trg_block_repeat_balance
  AFTER INSERT OR UPDATE OR DELETE
  ON public.coaching_workout_blocks
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_workout_block_balance();

COMMENT ON TRIGGER trg_block_repeat_balance
  ON public.coaching_workout_blocks IS
  'Deferred constraint trigger: validates repeat/repeat_end balance at '
  'transaction commit time so multi-row template edits (reorder, bulk '
  'insert) can be done atomically without intermediate-state failures.';

-- ─── 4. Sanity self-check: backfill produced a balanced state ─────────────────

DO $selfcheck$
DECLARE
  v_template_id UUID;
  v_failed_templates INT := 0;
BEGIN
  FOR v_template_id IN
    SELECT DISTINCT template_id
      FROM public.coaching_workout_blocks
     WHERE block_type IN ('repeat', 'repeat_end')
  LOOP
    BEGIN
      PERFORM public.fn_validate_workout_block_balance(v_template_id);
    EXCEPTION WHEN check_violation THEN
      v_failed_templates := v_failed_templates + 1;
      RAISE WARNING 'Template % failed balance self-check: %',
        v_template_id, SQLERRM;
    END;
  END LOOP;

  IF v_failed_templates > 0 THEN
    RAISE EXCEPTION
      'L05-21 backfill self-check failed: % templates still unbalanced. '
      'Migration aborted — manual triage required.',
      v_failed_templates;
  END IF;
END;
$selfcheck$;

COMMIT;
