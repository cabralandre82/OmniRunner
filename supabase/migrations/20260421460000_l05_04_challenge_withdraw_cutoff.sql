-- L05-04 — Challenge withdraw-cutoff column.
--
-- Before this migration an athlete could `challenge-withdraw`
-- at any time during an active challenge, including minutes before
-- the window closed. The product consequence was gaming: athletes
-- near last place would withdraw to avoid their score affecting
-- rankings, distorting the leaderboard and the gamification loop.
--
-- The fix is a per-challenge cutoff expressed in hours before
-- `ends_at_ms`. The Edge Function `challenge-withdraw` consults
-- this column and returns 422 WITHDRAW_LOCKED inside the cutoff.
--
-- Defaults:
--   - 48 hours for new challenges (industry consensus, matches
--     auditing finding prescription).
--   - 0 hours for any `type = 'one_vs_one'` — 1:1 duels already
--     burn coins on accept (L05-06 handles refund), and the
--     one-player party never wins by "attrition" from a withdraw
--     so the cutoff is not needed. Leaving it at 0 preserves the
--     current behaviour for duels.
--
-- Bounds: [0, 168] hours. Zero = withdrawals always allowed (the
-- pre-L05-04 behaviour). 168 hours = 7 days; longer than a week
-- would effectively forbid withdrawals on any challenge shorter
-- than the cutoff itself, which we treat as a configuration bug.

BEGIN;

ALTER TABLE public.challenges
  ADD COLUMN IF NOT EXISTS withdraw_cutoff_hours integer NOT NULL DEFAULT 48;

ALTER TABLE public.challenges
  DROP CONSTRAINT IF EXISTS challenges_withdraw_cutoff_hours_range;

ALTER TABLE public.challenges
  ADD CONSTRAINT challenges_withdraw_cutoff_hours_range
  CHECK (withdraw_cutoff_hours >= 0 AND withdraw_cutoff_hours <= 168);

COMMENT ON COLUMN public.challenges.withdraw_cutoff_hours IS
  'L05-04 — hours before ends_at_ms during which challenge-withdraw returns ' ||
  'WITHDRAW_LOCKED. 0 disables the cutoff (pre-L05-04 behaviour).';

-- Backfill heuristic:
--   - 1:1 challenges: no cutoff (preserve current behaviour)
--   - everything else: default 48h
-- New challenges picked up by the column default (48h).
UPDATE public.challenges
   SET withdraw_cutoff_hours = 0
 WHERE type = 'one_vs_one'
   AND withdraw_cutoff_hours = 48;

-- Self-test. Asserts:
--   (a) column exists with expected default,
--   (b) CHECK constraint blocks negative / > 168,
--   (c) duels were backfilled to 0.
DO $$
DECLARE
  v_default text;
  v_fail boolean;
  v_duels_zero int;
  v_duels_total int;
BEGIN
  SELECT column_default
    INTO v_default
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'challenges'
     AND column_name = 'withdraw_cutoff_hours';
  IF v_default IS NULL OR v_default NOT LIKE '48%' THEN
    RAISE EXCEPTION 'L05-04 self-test: default not 48 (got %)', v_default;
  END IF;

  BEGIN
    INSERT INTO public.challenges (
      creator_user_id, type, metric, window_ms, created_at_ms,
      withdraw_cutoff_hours
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      'group', 'distance', 604800000, 1700000000000, -1
    );
    v_fail := true;
  EXCEPTION WHEN OTHERS THEN
    v_fail := false;
  END;
  IF v_fail THEN
    RAISE EXCEPTION 'L05-04 self-test: CHECK did not block negative value';
  END IF;

  BEGIN
    INSERT INTO public.challenges (
      creator_user_id, type, metric, window_ms, created_at_ms,
      withdraw_cutoff_hours
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      'group', 'distance', 604800000, 1700000000000, 169
    );
    v_fail := true;
  EXCEPTION WHEN OTHERS THEN
    v_fail := false;
  END;
  IF v_fail THEN
    RAISE EXCEPTION 'L05-04 self-test: CHECK did not block value > 168';
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE withdraw_cutoff_hours = 0),
    COUNT(*)
  INTO v_duels_zero, v_duels_total
  FROM public.challenges
  WHERE type = 'one_vs_one';

  IF v_duels_total > 0 AND v_duels_zero <> v_duels_total THEN
    RAISE EXCEPTION
      'L05-04 self-test: duels backfill incomplete (% of % at 0)',
      v_duels_zero, v_duels_total;
  END IF;

  RAISE NOTICE 'L05-04 self-test: OK';
END
$$;

COMMIT;
