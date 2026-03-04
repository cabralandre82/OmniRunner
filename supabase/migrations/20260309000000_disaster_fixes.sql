-- =============================================================================
-- DISASTER FIX MIGRATION
-- Fixes all P0/P1/P2 issues from disaster simulation
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- C3 (P0): Block self-escalation of profiles.platform_role
-- Any authenticated user could PATCH their own platform_role to 'admin'
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_protect_platform_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.platform_role IS DISTINCT FROM NEW.platform_role THEN
    IF current_setting('role', true) <> 'service_role' THEN
      RAISE EXCEPTION 'platform_role cannot be changed by the user';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_platform_role ON profiles;
CREATE TRIGGER protect_platform_role
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION trg_protect_platform_role();

-- ─────────────────────────────────────────────────────────────────────────────
-- C4 (P0): Limit workout_delivery_events.meta payload size
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  ALTER TABLE workout_delivery_events
    ADD CONSTRAINT chk_delivery_event_meta_size
    CHECK (meta IS NULL OR octet_length(meta::text) < 65536);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- H6 (P1): increment_wallet_balance INSERT fallback needs ON CONFLICT
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.increment_wallet_balance(
  p_user_id uuid,
  p_delta integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO wallets (user_id, balance_coins, updated_at)
  VALUES (p_user_id, p_delta, now())
  ON CONFLICT (user_id)
  DO UPDATE SET
    balance_coins = wallets.balance_coins + p_delta,
    updated_at = now();
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- H7 (P1): challenge-join 1v1 capacity check with FOR UPDATE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_check_challenge_capacity(
  p_challenge_id uuid,
  p_max_participants integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM challenge_participants
  WHERE challenge_id = p_challenge_id
    AND status IN ('accepted', 'pending')
  FOR UPDATE;

  RETURN v_count < p_max_participants;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_check_challenge_capacity(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_check_challenge_capacity(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_check_challenge_capacity(uuid, integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- H8 (P1): fn_sum_coin_ledger_by_group — add membership check
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_sum_coin_ledger_by_group(
  p_group_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sum bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE user_id = auth.uid() AND group_id = p_group_id
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT COALESCE(SUM(delta_coins), 0)::bigint INTO v_sum
  FROM coin_ledger
  WHERE issuer_group_id = p_group_id;

  RETURN v_sum;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- H10 (P1): sessions.status CHECK constraint
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  ALTER TABLE sessions
    ADD CONSTRAINT chk_sessions_status
    CHECK (status BETWEEN 0 AND 10);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- H11 (P1): sessions.start_time_ms — prevent backdating beyond 7 days
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_validate_session_timestamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.start_time_ms < (EXTRACT(epoch FROM now() - interval '7 days') * 1000)::bigint THEN
    IF current_setting('role', true) <> 'service_role' THEN
      RAISE EXCEPTION 'session_too_old: start_time_ms cannot be more than 7 days in the past';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_session_timestamp ON sessions;
CREATE TRIGGER validate_session_timestamp
  BEFORE INSERT ON sessions
  FOR EACH ROW
  EXECUTE FUNCTION trg_validate_session_timestamp();

-- ─────────────────────────────────────────────────────────────────────────────
-- M4 (P2): Make Strava dedup index UNIQUE
-- ─────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS idx_sessions_strava_activity;
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_strava_activity
  ON public.sessions (user_id, strava_activity_id)
  WHERE strava_activity_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- M6 (P2): Fix support_tickets RLS to use current role names
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  DROP POLICY IF EXISTS support_tickets_staff_read ON support_tickets;
  CREATE POLICY support_tickets_staff_read ON support_tickets
    FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM coaching_members cm
        WHERE cm.user_id = auth.uid()
          AND cm.group_id = support_tickets.group_id
          AND cm.role IN ('admin_master', 'coach', 'assistant')
      )
      OR user_id = auth.uid()
    );
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- M8 (P2): workout_delivery_batches period validation
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  ALTER TABLE workout_delivery_batches
    ADD CONSTRAINT chk_delivery_batch_period
    CHECK (period_start IS NULL OR period_end IS NULL OR period_start <= period_end);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- M9 (P2): workout_delivery_events.type constraint
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  ALTER TABLE workout_delivery_events
    ADD CONSTRAINT chk_delivery_event_type
    CHECK (type IN (
      'BATCH_CREATED', 'MARK_PUBLISHED', 'ATHLETE_CONFIRMED',
      'ATHLETE_FAILED', 'STAFF_NOTE', 'STATUS_CHANGE'
    ));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- M14 (P2): coin_ledger.issuer_group_id FK (if coaching_groups exists)
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  ALTER TABLE coin_ledger
    ADD CONSTRAINT fk_coin_ledger_issuer_group
    FOREIGN KEY (issuer_group_id)
    REFERENCES coaching_groups (id)
    ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_table THEN NULL;
END $$;

COMMIT;
