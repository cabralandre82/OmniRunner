-- ============================================================================
-- Omni Runner — Challenge creation limits (DB-level enforcement)
-- Date: 2026-02-21
-- Sprint: 35.4.2
-- Origin: DECISAO 052 — Limites Operacionais do Sistema
-- ============================================================================
-- Enforces:
--   - Max 5 active challenges per athlete (status 'accepted' in participants)
--   - Max 10 pending challenges per athlete (status 'pending' target)
--   - Max 20 challenges created per athlete per UTC day
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_enforce_challenge_limits()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_count  int;
  v_created_today int;
BEGIN
  -- Limit 1: max 20 challenges created per user per UTC day
  SELECT count(*) INTO v_created_today
    FROM public.challenges
    WHERE creator_user_id = NEW.creator_user_id
      AND created_at_ms >= (extract(epoch FROM date_trunc('day', now() AT TIME ZONE 'UTC')) * 1000)::bigint;

  IF v_created_today >= 20 THEN
    RAISE EXCEPTION 'DAILY_CHALLENGE_LIMIT: max 20 challenges per day'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_challenge_creation_limit ON public.challenges;
CREATE TRIGGER trg_challenge_creation_limit
  BEFORE INSERT ON public.challenges
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_enforce_challenge_limits();

-- Limit 2: max 5 active + max 10 pending per athlete (on participant insert/update)
CREATE OR REPLACE FUNCTION public.fn_enforce_participant_limits()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active  int;
  v_pending int;
BEGIN
  IF NEW.status = 'accepted' THEN
    SELECT count(*) INTO v_active
      FROM public.challenge_participants
      WHERE user_id = NEW.user_id
        AND status = 'accepted'
        AND challenge_id != NEW.challenge_id;

    IF v_active >= 5 THEN
      RAISE EXCEPTION 'ACTIVE_CHALLENGE_LIMIT: max 5 active challenges per athlete'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF NEW.status = 'pending' THEN
    SELECT count(*) INTO v_pending
      FROM public.challenge_participants
      WHERE user_id = NEW.user_id
        AND status = 'pending'
        AND challenge_id != NEW.challenge_id;

    IF v_pending >= 10 THEN
      RAISE EXCEPTION 'PENDING_CHALLENGE_LIMIT: max 10 pending challenges per athlete'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_participant_limits ON public.challenge_participants;
CREATE TRIGGER trg_participant_limits
  BEFORE INSERT OR UPDATE ON public.challenge_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_enforce_participant_limits();

COMMIT;
