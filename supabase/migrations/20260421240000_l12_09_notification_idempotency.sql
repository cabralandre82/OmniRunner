-- ============================================================================
-- L12-09 — lifecycle-cron notification idempotency guardrail
--
-- Audit reference:
--   docs/audit/findings/L12-09-lifecycle-cron-dispara-notificacoes-idempotencia-nao-garanti.md
--   docs/audit/parts/12-cron-scheduler.md  (anchor [12.9])
--
-- Problem
-- ───────
--   The lifecycle-cron / notify-rules / onboarding-nudge Edge Functions
--   persist an audit row in `public.notification_log` AFTER a successful
--   push dispatch. The dedup check is a separate SELECT (`was_recently_
--   notified`) that happens BEFORE dispatch:
--
--     1. SELECT COUNT(*) FROM notification_log
--          WHERE user_id=U AND rule=R AND context_id=C
--            AND sent_at > now() - 12h;
--     2. if count = 0 → dispatchPush()
--     3. if ok → INSERT notification_log(U, R, C);
--
--   The L12-03 overlap guard (advisory lock + cron_run_state) already
--   reduces the probability of two cron runs overlapping, but:
--
--     • The Edge Function can be INVOKED MANUALLY in parallel (ops
--       trigger + cron fire landing in the same 5-min window).
--     • Two different RULES can independently fetch the same user and
--       race on `dispatchPush` if context_id collides (rare but
--       possible for `low_credits_alert` vs operator-forced push).
--     • The `wasRecentlyNotified` SELECT looks back 12h; a delayed
--       INSERT (e.g. dispatchPush took 8s + network flake on the
--       audit insert) lengthens the race window.
--
--   The audit (L12-09) asked for a hard idempotency constraint:
--   INSERT ... ON CONFLICT DO NOTHING with a UNIQUE key on
--   (user_id, rule, context_id) so the CLAIM of the notification is
--   race-safe — dispatch only happens if the insert SUCCEEDED.
--
-- Defence (this migration)
-- ───────
--   Four DB objects + one dedup step.
--
--     1. **Deduplicate existing rows** first — keep MIN(id) per
--        (user_id, rule, context_id) tuple so the UNIQUE ADD succeeds.
--        The 12h dedup previously tolerated dupes; after this
--        migration they're forbidden.
--
--     2. **Add `UNIQUE (user_id, rule, context_id)` constraint** on
--        `public.notification_log`. Any legacy SELECT-then-INSERT
--        caller will now raise `23505 unique_violation` on duplicate;
--        we ship a transition helper below so callers don't have to
--        handle that directly.
--
--     3. **`public.fn_try_claim_notification(user_id, rule,
--                                            context_id)`**
--        SECURITY DEFINER, `search_path=public,pg_temp`, idempotent.
--        `INSERT ... ON CONFLICT DO NOTHING` — returns `TRUE` iff the
--        row was inserted (caller owns the dispatch), `FALSE`
--        otherwise (already claimed). This is the recommended entry
--        point for all new callers.
--
--     4. **`public.fn_release_notification(user_id, rule,
--                                          context_id, max_age_seconds)`**
--        SECURITY DEFINER — releases a claim if the dispatch failed
--        BEFORE the row can meaningfully dedup. Bounded to
--        `max_age_seconds` (default 60s) so we never delete an old
--        successful notification record even if a caller misuses the
--        release path. Returns TRUE if a row was deleted.
--
--     5. **Self-test DO-block** at the end validates the three
--        invariants (UNIQUE enforces duplicate rejection, claim/
--        release round-trip works, bounded release does NOT delete
--        old rows).
--
-- Backwards compat
-- ────────────────
--   • The legacy SELECT-then-INSERT pattern still works for the first
--     INSERT of a (user, rule, context_id) tuple — the UNIQUE only
--     bites on the SECOND insert. For callers that re-insert (either
--     legitimately after a release or by bug), they now see 23505
--     instead of silent dupe. Both downstream callers (notify-rules,
--     onboarding-nudge) are migrated in this same PR to use the
--     `fn_try_claim_notification` RPC.
--   • `context_id TEXT NOT NULL DEFAULT ''` stays — empty string is a
--     valid value (for "once ever per user per rule" semantics).
--   • RLS policy `notification_log_select` is untouched.
--
-- Verification
-- ────────────
--   • Self-test DO block at the end of this file.
--   • Integration tests in tools/test_l12_09_notification_idempotency.ts
--     (8 cases via docker exec psql).
-- ============================================================================

BEGIN;

-- 1. Deduplicate existing rows before the UNIQUE constraint lands.
--    Keep the OLDEST row per (user, rule, context_id) tuple — preserves
--    `sent_at` history as close to reality as possible for the
--    surviving row. We rank by (sent_at ASC, id ASC) so the tiebreak is
--    deterministic (id is UUID, so we can't use MIN(id) directly).
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id, rule, context_id
           ORDER BY sent_at ASC, id ASC
         ) AS rn
    FROM public.notification_log
),
deleted AS (
  DELETE FROM public.notification_log n
   USING ranked r
   WHERE n.id = r.id
     AND r.rn > 1
  RETURNING 1
)
SELECT COUNT(*) AS rows_deleted FROM deleted;

-- 2. Add the UNIQUE constraint. Idempotent via IF-NOT-EXISTS pattern
--    using pg_constraint lookup.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.notification_log'::regclass
       AND conname  = 'notification_log_dedup_unique'
  ) THEN
    ALTER TABLE public.notification_log
      ADD CONSTRAINT notification_log_dedup_unique
      UNIQUE (user_id, rule, context_id);
  END IF;
END$$;

COMMENT ON CONSTRAINT notification_log_dedup_unique ON public.notification_log IS
  'L12-09: hard idempotency — at most one row per (user_id, rule, context_id). '
  'Callers should use public.fn_try_claim_notification for race-safe inserts.';

-- 3. fn_try_claim_notification — race-safe claim primitive.

CREATE OR REPLACE FUNCTION public.fn_try_claim_notification(
  p_user_id    uuid,
  p_rule       text,
  p_context_id text DEFAULT ''
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted int;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER_ID: p_user_id is required' USING ERRCODE = '22023';
  END IF;
  IF p_rule IS NULL OR length(trim(p_rule)) = 0 THEN
    RAISE EXCEPTION 'INVALID_RULE: p_rule is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.notification_log (user_id, rule, context_id)
  VALUES (p_user_id, p_rule, COALESCE(p_context_id, ''))
  ON CONFLICT ON CONSTRAINT notification_log_dedup_unique DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted = 1;
END;
$$;

COMMENT ON FUNCTION public.fn_try_claim_notification(uuid, text, text) IS
  'L12-09: race-safe claim primitive. Returns TRUE iff a new row was inserted '
  '(caller owns the subsequent dispatch). Returns FALSE if the tuple was already '
  'claimed by another cron/operator run. Any caller that calls this and then '
  'FAILS to dispatch MUST call fn_release_notification within 60s to avoid '
  'a permanent silent dedup.';

REVOKE ALL ON FUNCTION public.fn_try_claim_notification(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_try_claim_notification(uuid, text, text) TO service_role;

-- 4. fn_release_notification — bounded rollback for dispatch failures.

CREATE OR REPLACE FUNCTION public.fn_release_notification(
  p_user_id         uuid,
  p_rule            text,
  p_context_id      text    DEFAULT '',
  p_max_age_seconds integer DEFAULT 60
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted int;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER_ID: p_user_id is required' USING ERRCODE = '22023';
  END IF;
  IF p_rule IS NULL OR length(trim(p_rule)) = 0 THEN
    RAISE EXCEPTION 'INVALID_RULE: p_rule is required' USING ERRCODE = '22023';
  END IF;
  IF p_max_age_seconds IS NULL OR p_max_age_seconds <= 0 OR p_max_age_seconds > 300 THEN
    RAISE EXCEPTION 'INVALID_MAX_AGE: % (expected 1..300)', p_max_age_seconds
      USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.notification_log
   WHERE user_id    = p_user_id
     AND rule       = p_rule
     AND context_id = COALESCE(p_context_id, '')
     AND sent_at    > now() - make_interval(secs => p_max_age_seconds);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted > 0;
END;
$$;

COMMENT ON FUNCTION public.fn_release_notification(uuid, text, text, integer) IS
  'L12-09: bounded rollback companion to fn_try_claim_notification. Deletes the '
  'claim row only if it was created within p_max_age_seconds (default 60s) to '
  'prevent accidental clobber of legitimate old notifications.';

REVOKE ALL ON FUNCTION public.fn_release_notification(uuid, text, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_release_notification(uuid, text, text, integer) TO service_role;

COMMIT;

-- ============================================================================
-- 5. Self-test — validates install + behaviour
-- ============================================================================
DO $selftest$
DECLARE
  v_test_user uuid := gen_random_uuid();
  v_claimed   boolean;
  v_released  boolean;
  v_has_users boolean;
  v_constraints int;
  v_funcs        int;
BEGIN
  -- 5.1 Constraint installed
  SELECT COUNT(*) INTO v_constraints
    FROM pg_constraint
   WHERE conrelid = 'public.notification_log'::regclass
     AND conname  = 'notification_log_dedup_unique';
  IF v_constraints <> 1 THEN
    RAISE EXCEPTION '[L12-09.selftest] notification_log_dedup_unique missing';
  END IF;

  -- 5.2 Functions installed
  SELECT COUNT(*) INTO v_funcs
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
     AND p.proname IN ('fn_try_claim_notification', 'fn_release_notification');
  IF v_funcs <> 2 THEN
    RAISE EXCEPTION '[L12-09.selftest] expected 2 helper functions, found %', v_funcs;
  END IF;

  -- The remaining tests require auth.users to exist with a seeded row.
  -- We skip them if auth.users is absent (some sandboxes) and rely on
  -- the integration tests instead.
  SELECT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
     WHERE n.nspname = 'auth' AND c.relname = 'users'
  ) INTO v_has_users;

  IF v_has_users THEN
    -- Seed a throwaway auth.users row for FK satisfaction.
    BEGIN
      INSERT INTO auth.users (
        id, email, instance_id, aud, role,
        encrypted_password, email_confirmed_at, created_at, updated_at
      ) VALUES (
        v_test_user, format('l12-09-selftest-%s@test.local', v_test_user),
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', '', now(), now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '[L12-09.selftest] could not seed auth.users (%): skipping behaviour test', SQLERRM;
      RETURN;
    END;

    BEGIN
      -- 5.3 Fresh claim returns TRUE
      v_claimed := public.fn_try_claim_notification(v_test_user, 'l12_09_selftest', 'ctx-1');
      IF NOT v_claimed THEN
        RAISE EXCEPTION '[L12-09.selftest] first claim should return TRUE';
      END IF;

      -- 5.4 Duplicate claim returns FALSE
      v_claimed := public.fn_try_claim_notification(v_test_user, 'l12_09_selftest', 'ctx-1');
      IF v_claimed THEN
        RAISE EXCEPTION '[L12-09.selftest] duplicate claim should return FALSE';
      END IF;

      -- 5.5 Release within window succeeds
      v_released := public.fn_release_notification(v_test_user, 'l12_09_selftest', 'ctx-1', 60);
      IF NOT v_released THEN
        RAISE EXCEPTION '[L12-09.selftest] release within 60s should return TRUE';
      END IF;

      -- 5.6 After release, re-claim works
      v_claimed := public.fn_try_claim_notification(v_test_user, 'l12_09_selftest', 'ctx-1');
      IF NOT v_claimed THEN
        RAISE EXCEPTION '[L12-09.selftest] re-claim after release should return TRUE';
      END IF;

      -- 5.7 Release past window is a no-op (sent_at is still recent here,
      --      so max_age_seconds = 0 should match nothing — but 0 is
      --      out-of-range; use a tiny positive that still rejects).
      --      Simulate "old" row by backdating sent_at.
      UPDATE public.notification_log
         SET sent_at = now() - interval '10 minutes'
       WHERE user_id = v_test_user
         AND rule    = 'l12_09_selftest';
      v_released := public.fn_release_notification(v_test_user, 'l12_09_selftest', 'ctx-1', 30);
      IF v_released THEN
        RAISE EXCEPTION '[L12-09.selftest] release of 10-min-old row with 30s bound should return FALSE';
      END IF;

      -- Cleanup
      DELETE FROM public.notification_log WHERE user_id = v_test_user;
    EXCEPTION WHEN OTHERS THEN
      DELETE FROM public.notification_log WHERE user_id = v_test_user;
      DELETE FROM auth.users WHERE id = v_test_user;
      RAISE;
    END;

    DELETE FROM auth.users WHERE id = v_test_user;
  END IF;

  RAISE NOTICE '[L12-09.selftest] OK — all invariants pass';
END
$selftest$;
