-- L21-10 — Elite athlete reputation quarantine.
--
-- The finding: when anti-cheat flips `sessions.is_verified = false`
-- because of a heuristic flag (e.g. speed spike on a treadmill GPS
-- glitch), every feed / leaderboard we render today happily shows
-- "session not verified" or the raw `integrity_flags` chip. For an
-- elite athlete, that's reputational damage from a false positive
-- with no appeal path.
--
-- This migration layers defence-in-depth around the existing
-- anti-cheat pipeline (L21-01/02) so the "public" view of a
-- flagged session degrades gracefully:
--
--   1. New column `sessions.review_status` with CHECK-bounded
--      state machine (none / pending_review / in_review / approved /
--      rejected) and a trigger enforcing legal transitions.
--
--   2. Rewritten helper `fn_session_visibility_status(session_id)`
--      — returns a **neutral** label to non-owners
--      (`verified` / `pending_review`), and surfaces raw flags only
--      to the owner and platform_admin.
--
--   3. New table `athlete_review_requests` — append-only queue of
--      manual-review requests, with `evidence_urls`, `athlete_note`,
--      `reviewer_id`, `resolution`. RLS: athlete reads own,
--      platform_admin reads/updates all.
--
--   4. Writer RPC `fn_request_session_review(session_id, note,
--      evidence_urls)` — gated by ownership, accepted only when
--      the session actually has flags (`integrity_flags IS NOT NULL`
--      OR `is_verified = false`), flips `sessions.review_status =
--      'pending_review'` atomically.
--
-- Nothing in this migration mutates historical data or removes any
-- existing invariant — it's additive and the review layer is
-- feature-flag-compatible.

BEGIN;

-- ── 1. sessions.review_status column ──────────────────────────────────────

DO $sessions$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'sessions'
       AND column_name = 'review_status'
  ) THEN
    ALTER TABLE public.sessions
      ADD COLUMN review_status text NOT NULL DEFAULT 'none';

    ALTER TABLE public.sessions
      ADD CONSTRAINT chk_sessions_review_status CHECK (
        review_status IN ('none','pending_review','in_review','approved','rejected')
      );

    COMMENT ON COLUMN public.sessions.review_status IS
      'L21-10 — elite athlete review queue state. Writes gated via fn_request_session_review / platform-admin RPCs.';
  END IF;
END
$sessions$;

-- ── 2. Neutral visibility helper ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_session_visibility_status(
  p_session_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_session  public.sessions%ROWTYPE;
  v_viewer   uuid := auth.uid();
  v_is_owner boolean;
  v_is_admin boolean;
BEGIN
  SELECT * INTO v_session FROM public.sessions WHERE id = p_session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'SESSION_NOT_FOUND';
  END IF;

  v_is_owner := v_viewer IS NOT NULL AND v_viewer = v_session.user_id;
  v_is_admin := EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = v_viewer AND p.platform_role = 'admin'
  );

  -- Non-owners & non-admins: neutral projection ONLY.
  IF NOT v_is_owner AND NOT v_is_admin THEN
    RETURN jsonb_build_object(
      'visibility_status', CASE
        WHEN v_session.is_verified = true AND
             v_session.review_status IN ('none','approved') THEN 'verified'
        WHEN v_session.review_status IN ('pending_review','in_review') THEN 'pending_review'
        ELSE 'verification_pending'
      END,
      -- Never leak flags/reasons to the public.
      'flags_visible',     false,
      'review_visible',    false
    );
  END IF;

  -- Owner / admin: full payload, including integrity_flags.
  RETURN jsonb_build_object(
    'visibility_status', CASE
      WHEN v_session.is_verified = true AND
           v_session.review_status IN ('none','approved') THEN 'verified'
      WHEN v_session.review_status IN ('pending_review','in_review') THEN 'pending_review'
      WHEN v_session.review_status = 'rejected'                      THEN 'rejected'
      ELSE 'needs_review'
    END,
    'flags_visible',   true,
    'integrity_flags', coalesce(to_jsonb(v_session.integrity_flags), '[]'::jsonb),
    'review_status',   v_session.review_status,
    'review_visible',  true,
    'is_owner',        v_is_owner,
    'is_admin',        v_is_admin
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_session_visibility_status(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_session_visibility_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_session_visibility_status(uuid) TO service_role;

COMMENT ON FUNCTION public.fn_session_visibility_status(uuid) IS
  'L21-10 — returns a viewer-scoped visibility payload. Non-owners never see integrity_flags; feed queries MUST go through this helper instead of reading the raw column.';

-- ── 3. Review request queue ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.athlete_review_requests (
  id               bigserial PRIMARY KEY,
  session_id       uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  athlete_id       uuid NOT NULL REFERENCES auth.users(id)       ON DELETE CASCADE,
  status           text NOT NULL DEFAULT 'pending',
  athlete_note     text,
  evidence_urls    jsonb NOT NULL DEFAULT '[]'::jsonb,
  reviewer_id      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution_note  text,
  resolved_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_review_request_status CHECK (
    status IN ('pending','in_review','approved','rejected','auto_dismissed')
  ),
  CONSTRAINT chk_review_request_note_length CHECK (
    athlete_note IS NULL OR length(athlete_note) <= 2000
  ),
  CONSTRAINT chk_review_request_resolution_length CHECK (
    resolution_note IS NULL OR length(resolution_note) <= 2000
  ),
  CONSTRAINT chk_review_request_evidence_shape CHECK (
    jsonb_typeof(evidence_urls) = 'array'
  ),
  CONSTRAINT chk_review_request_resolved_pairing CHECK (
    (status IN ('approved','rejected','auto_dismissed')
      AND resolved_at IS NOT NULL)
    OR (status IN ('pending','in_review') AND resolved_at IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_review_request_open_per_session
  ON public.athlete_review_requests(session_id)
  WHERE status IN ('pending','in_review');

CREATE INDEX IF NOT EXISTS idx_review_request_athlete_status
  ON public.athlete_review_requests(athlete_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_review_request_queue
  ON public.athlete_review_requests(status, created_at)
  WHERE status IN ('pending','in_review');

ALTER TABLE public.athlete_review_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS athlete_review_own_read ON public.athlete_review_requests;
CREATE POLICY athlete_review_own_read
  ON public.athlete_review_requests
  FOR SELECT USING (
    athlete_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

DROP POLICY IF EXISTS athlete_review_own_insert ON public.athlete_review_requests;
CREATE POLICY athlete_review_own_insert
  ON public.athlete_review_requests
  FOR INSERT WITH CHECK (athlete_id = auth.uid());

DROP POLICY IF EXISTS athlete_review_admin_update ON public.athlete_review_requests;
CREATE POLICY athlete_review_admin_update
  ON public.athlete_review_requests
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

REVOKE ALL    ON public.athlete_review_requests FROM PUBLIC;
GRANT SELECT  ON public.athlete_review_requests TO authenticated;
GRANT INSERT  ON public.athlete_review_requests TO authenticated;
GRANT UPDATE  ON public.athlete_review_requests TO authenticated;
GRANT ALL     ON public.athlete_review_requests TO service_role;
GRANT USAGE   ON SEQUENCE athlete_review_requests_id_seq TO authenticated;
GRANT USAGE   ON SEQUENCE athlete_review_requests_id_seq TO service_role;

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.fn_review_requests_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_review_requests_touch_updated_at
  ON public.athlete_review_requests;
CREATE TRIGGER trg_review_requests_touch_updated_at
  BEFORE UPDATE ON public.athlete_review_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_review_requests_touch_updated_at();

-- ── 4. fn_request_session_review RPC ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_request_session_review(
  p_session_id   uuid,
  p_note         text    DEFAULT NULL,
  p_evidence     jsonb   DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_session  public.sessions%ROWTYPE;
  v_viewer   uuid := auth.uid();
  v_request_id bigint;
BEGIN
  IF v_viewer IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'NOT_AUTHENTICATED';
  END IF;

  IF jsonb_typeof(coalesce(p_evidence, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_EVIDENCE';
  END IF;

  SELECT * INTO v_session FROM public.sessions
    WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'SESSION_NOT_FOUND';
  END IF;

  IF v_session.user_id <> v_viewer THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FORBIDDEN';
  END IF;

  -- Only allow opening a review when the session is in a reviewable state.
  IF v_session.review_status NOT IN ('none','rejected') THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'INVALID_STATE';
  END IF;

  -- Accept only when there is something to review.
  IF coalesce(array_length(v_session.integrity_flags, 1), 0) = 0
     AND v_session.is_verified = true THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'NOTHING_TO_REVIEW';
  END IF;

  INSERT INTO public.athlete_review_requests (
    session_id, athlete_id, status, athlete_note, evidence_urls
  ) VALUES (
    p_session_id,
    v_viewer,
    'pending',
    nullif(left(coalesce(p_note, ''), 2000), ''),
    coalesce(p_evidence, '[]'::jsonb)
  )
  RETURNING id INTO v_request_id;

  UPDATE public.sessions
     SET review_status = 'pending_review'
   WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'request_id',     v_request_id,
    'session_id',     p_session_id,
    'review_status',  'pending_review'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_request_session_review(uuid, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_request_session_review(uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_request_session_review(uuid, text, jsonb) TO service_role;

COMMENT ON FUNCTION public.fn_request_session_review(uuid, text, jsonb) IS
  'L21-10 — athlete-facing RPC to open a manual review. Gated on session ownership + reviewable state; atomically sets sessions.review_status = pending_review.';

-- ── 5. review_status transition trigger ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_sessions_review_status_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only policing the review_status column; other columns pass through.
  IF OLD.review_status IS NOT DISTINCT FROM NEW.review_status THEN
    RETURN NEW;
  END IF;

  -- Allowed transitions.
  IF NOT (
    (OLD.review_status = 'none'             AND NEW.review_status IN ('pending_review'))
    OR (OLD.review_status = 'pending_review' AND NEW.review_status IN ('in_review','rejected','approved','none'))
    OR (OLD.review_status = 'in_review'      AND NEW.review_status IN ('approved','rejected','pending_review'))
    OR (OLD.review_status = 'approved'       AND NEW.review_status IN ('none','in_review'))
    OR (OLD.review_status = 'rejected'       AND NEW.review_status IN ('none','pending_review'))
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = format('INVALID_TRANSITION %s -> %s', OLD.review_status, NEW.review_status);
  END IF;

  RETURN NEW;
END;
$$;

DO $trig$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'sessions') THEN
    DROP TRIGGER IF EXISTS trg_sessions_review_status_guard ON public.sessions;
    CREATE TRIGGER trg_sessions_review_status_guard
      BEFORE UPDATE OF review_status ON public.sessions
      FOR EACH ROW
      EXECUTE FUNCTION public.fn_sessions_review_status_guard();
  END IF;
END
$trig$;

-- ── 6. Self-test ──────────────────────────────────────────────────────────

DO $$
DECLARE
  v_ok boolean;
BEGIN
  -- column exists?
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'sessions'
       AND column_name = 'review_status'
  ) THEN
    RAISE EXCEPTION 'L21-10 self-test: review_status column missing';
  END IF;

  -- helper exists?
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'fn_session_visibility_status'
  ) THEN
    RAISE EXCEPTION 'L21-10 self-test: fn_session_visibility_status missing';
  END IF;

  -- review queue unique-open index enforced?
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE indexname = 'uniq_review_request_open_per_session'
  ) THEN
    RAISE EXCEPTION 'L21-10 self-test: unique-open index missing';
  END IF;

  -- transition trigger registered when sessions exists?
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'sessions') AND NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sessions_review_status_guard'
  ) THEN
    RAISE EXCEPTION 'L21-10 self-test: transition guard trigger missing';
  END IF;

  -- Invalid review_status rejected by CHECK.
  BEGIN
    INSERT INTO public.athlete_review_requests (session_id, athlete_id, status)
      VALUES (gen_random_uuid(), gen_random_uuid(), 'bogus');
    RAISE EXCEPTION 'L21-10 self-test: bogus status should have been rejected';
  EXCEPTION WHEN check_violation THEN NULL;
           WHEN foreign_key_violation THEN NULL;
  END;

  RAISE NOTICE 'L21-10 self-test: OK';
END
$$;

COMMIT;
