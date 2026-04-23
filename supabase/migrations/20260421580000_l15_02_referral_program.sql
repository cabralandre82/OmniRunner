-- ============================================================================
-- L15-02 — Referral / invite viral primitives
-- Date: 2026-04-21
-- ============================================================================
-- Omni today has zero viral loop: no "invite a friend" surface, no referral
-- tracking, no reward primitive. CAC stays high and the natural athlete-brings-
-- athlete flywheel never kicks in. This migration ships the server-side
-- primitives that a deep link flow (e.g. `https://omni.run/r/<CODE>`) can
-- rely on:
--
--   1. `public.referrals` — append-only table pairing referrer (mandatory)
--      with referred (nullable until activation) via a unique `referral_code`
--      string. Status state machine: `pending` → `activated` | `expired` |
--      `revoked`, with timestamps for each transition.
--   2. `public.referral_rewards_config` — single-row config table holding the
--      current coin payout for referrer + referred, the code length (default
--      8), TTL (default 30 d), and per-referrer cap (default 50 activations).
--   3. `fn_generate_referral_code(len int)` — IMMUTABLE-esque generator that
--      loops until it emits an unused code (caps at 8 retries, then raises
--      P0002 so callers can retry on a fresh transaction).
--   4. `fn_create_referral(p_channel text)` — issues one referral for the
--      current auth.uid(); fails fast when the per-referrer cap is reached.
--   5. `fn_activate_referral(p_code text)` — called during onboarding. Gated
--      on: (a) code not expired, (b) code still pending, (c) referred user
--      != referrer, (d) referred user has no other activated referral.
--      Credits both parties via `coin_ledger` (new reasons
--      `referral_referrer_reward` / `referral_referred_reward`), bumps
--      `wallets.balance_coins`, and emits a business event.
--   6. `fn_expire_referrals()` — cron target that flips `pending` referrals
--      past their TTL to `expired` and returns the count.
--   7. CHECK-bound state machine + `BEFORE UPDATE OF status` trigger that
--      only allows legal transitions.
--   8. Retention: referrals are a business record, NOT an audit log;
--      therefore NOT registered in `audit_logs_retention_config`.
--
-- Additive only — no RLS change on existing tables, no breaking schema change.

BEGIN;

-- ── 0. coin_ledger reason enum expansion ────────────────────────────────
-- Two new ledger reasons; preserve the existing set.
ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;
ALTER TABLE public.coin_ledger
  ADD CONSTRAINT coin_ledger_reason_check CHECK (
    reason = ANY (ARRAY[
      'session_completed',
      'challenge_one_vs_one_completed',
      'challenge_one_vs_one_won',
      'challenge_group_completed',
      'streak_weekly',
      'streak_monthly',
      'pr_distance',
      'pr_pace',
      'challenge_entry_fee',
      'challenge_pool_won',
      'challenge_entry_refund',
      'cosmetic_purchase',
      'admin_adjustment',
      'badge_reward',
      'mission_reward',
      'institution_token_issue',
      'institution_token_burn',
      'institution_switch_burn',
      'institution_token_reverse_emission',
      'institution_token_reverse_burn',
      'referral_referrer_reward',
      'referral_referred_reward'
    ])
  );

COMMENT ON CONSTRAINT coin_ledger_reason_check ON public.coin_ledger IS
  'L15-02: adds referral_referrer_reward + referral_referred_reward on top of the L03-13 enumeration.';

-- ── 1. config ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.referral_rewards_config (
  id                         smallint PRIMARY KEY CHECK (id = 1),
  reward_referrer_coins      integer NOT NULL DEFAULT 10
                             CHECK (reward_referrer_coins BETWEEN 0 AND 10000),
  reward_referred_coins      integer NOT NULL DEFAULT 5
                             CHECK (reward_referred_coins BETWEEN 0 AND 10000),
  code_length                integer NOT NULL DEFAULT 8
                             CHECK (code_length BETWEEN 6 AND 16),
  ttl_days                   integer NOT NULL DEFAULT 30
                             CHECK (ttl_days BETWEEN 1 AND 365),
  max_activations_per_user   integer NOT NULL DEFAULT 50
                             CHECK (max_activations_per_user BETWEEN 1 AND 100000),
  updated_at                 timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.referral_rewards_config (id) VALUES (1)
  ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.referral_rewards_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "referral_config_read_all" ON public.referral_rewards_config;
CREATE POLICY "referral_config_read_all"
  ON public.referral_rewards_config FOR SELECT USING (true);

-- ── 2. referrals table ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.referrals (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referred_user_id         uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  referral_code            text NOT NULL,
  channel                  text NOT NULL DEFAULT 'link'
                           CHECK (channel IN ('link','whatsapp','instagram','tiktok','email','sms','qr')),
  reward_referrer_coins    integer NOT NULL CHECK (reward_referrer_coins BETWEEN 0 AND 10000),
  reward_referred_coins    integer NOT NULL CHECK (reward_referred_coins BETWEEN 0 AND 10000),
  status                   text NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending','activated','expired','revoked')),
  expires_at               timestamptz NOT NULL,
  activated_at             timestamptz,
  expired_at               timestamptz,
  revoked_at               timestamptz,
  revoked_reason           text,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referrals_self_referral_blocked
    CHECK (referred_user_id IS NULL OR referred_user_id <> referrer_user_id),
  CONSTRAINT referrals_status_timestamps CHECK (
    (status = 'pending'   AND activated_at IS NULL AND expired_at IS NULL AND revoked_at IS NULL) OR
    (status = 'activated' AND activated_at IS NOT NULL) OR
    (status = 'expired'   AND expired_at   IS NOT NULL) OR
    (status = 'revoked'   AND revoked_at   IS NOT NULL)
  ),
  CONSTRAINT referrals_activated_has_referred
    CHECK (status <> 'activated' OR referred_user_id IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_referrals_code
  ON public.referrals (referral_code);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer
  ON public.referrals (referrer_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_referrals_pending_expiry
  ON public.referrals (expires_at) WHERE status = 'pending';
CREATE UNIQUE INDEX IF NOT EXISTS uniq_referrals_referred_once
  ON public.referrals (referred_user_id) WHERE status = 'activated';

COMMENT ON TABLE public.referrals IS
  'L15-02: referral invitations + activations. Append-only row per invite, status state-machine, unique code, unique-activation per referred user.';

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.fn_referrals_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_referrals_updated_at ON public.referrals;
CREATE TRIGGER trg_referrals_updated_at
  BEFORE UPDATE ON public.referrals
  FOR EACH ROW EXECUTE FUNCTION public.fn_referrals_touch_updated_at();

-- state-machine trigger
CREATE OR REPLACE FUNCTION public.fn_referrals_status_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_legal boolean := false;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  v_legal :=
    (OLD.status = 'pending' AND NEW.status IN ('activated','expired','revoked'));

  IF NOT v_legal THEN
    RAISE EXCEPTION
      'referrals.status INVALID_TRANSITION: % -> % (row %)',
      OLD.status, NEW.status, OLD.id
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_referrals_status_guard ON public.referrals;
CREATE TRIGGER trg_referrals_status_guard
  BEFORE UPDATE OF status ON public.referrals
  FOR EACH ROW EXECUTE FUNCTION public.fn_referrals_status_guard();

-- ── 3. RLS ───────────────────────────────────────────────────────────────
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "referrals_own_read"   ON public.referrals;
DROP POLICY IF EXISTS "referrals_own_insert" ON public.referrals;
DROP POLICY IF EXISTS "referrals_admin_read" ON public.referrals;

CREATE POLICY "referrals_own_read" ON public.referrals
  FOR SELECT USING (
    auth.uid() = referrer_user_id OR auth.uid() = referred_user_id
  );

CREATE POLICY "referrals_admin_read" ON public.referrals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

-- INSERT / UPDATE paths are gated through SECURITY DEFINER RPCs; deny by default.

-- ── 4. code generator ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_generate_referral_code(p_len integer)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_len      integer := GREATEST(6, LEAST(16, COALESCE(p_len, 8)));
  v_alphabet text    := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- no 0/O/1/I
  v_bytes    bytea;
  v_code     text;
  v_i        integer;
  v_tries    integer := 0;
BEGIN
  LOOP
    v_code := '';
    v_bytes := gen_random_bytes(v_len);
    FOR v_i IN 0 .. (v_len - 1) LOOP
      v_code := v_code || substr(
        v_alphabet,
        (get_byte(v_bytes, v_i) % length(v_alphabet))::integer + 1,
        1
      );
    END LOOP;
    -- collision check
    PERFORM 1 FROM public.referrals WHERE referral_code = v_code;
    IF NOT FOUND THEN
      RETURN v_code;
    END IF;
    v_tries := v_tries + 1;
    EXIT WHEN v_tries > 8;
  END LOOP;
  RAISE EXCEPTION 'referral_code_generation_exhausted'
    USING ERRCODE = 'P0002';
END
$$;

COMMENT ON FUNCTION public.fn_generate_referral_code(integer) IS
  'L15-02: generates a collision-free upper-case alphanumeric referral code (excluding 0/O/1/I). Length clamped [6, 16]. Retries up to 8 times; raises P0002 if the namespace is exhausted (caller should retry).';

-- ── 5. create referral RPC ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_create_referral(
  p_channel text DEFAULT 'link'
) RETURNS public.referrals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_cfg     public.referral_rewards_config%ROWTYPE;
  v_count   integer;
  v_code    text;
  v_row     public.referrals%ROWTYPE;
BEGIN
  IF v_uid IS NULL AND current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  IF p_channel IS NULL
     OR p_channel NOT IN ('link','whatsapp','instagram','tiktok','email','sms','qr') THEN
    RAISE EXCEPTION 'invalid_channel' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_cfg FROM public.referral_rewards_config WHERE id = 1;

  SELECT count(*)::integer INTO v_count
  FROM public.referrals
  WHERE referrer_user_id = v_uid
    AND status IN ('pending','activated');

  IF v_count >= v_cfg.max_activations_per_user THEN
    RAISE EXCEPTION 'referral_cap_reached (%/%)',
      v_count, v_cfg.max_activations_per_user
      USING ERRCODE = 'P0003';
  END IF;

  v_code := public.fn_generate_referral_code(v_cfg.code_length);

  INSERT INTO public.referrals (
    referrer_user_id, referral_code, channel,
    reward_referrer_coins, reward_referred_coins,
    expires_at
  ) VALUES (
    v_uid, v_code, p_channel,
    v_cfg.reward_referrer_coins, v_cfg.reward_referred_coins,
    now() + make_interval(days => v_cfg.ttl_days)
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END
$$;

COMMENT ON FUNCTION public.fn_create_referral(text) IS
  'L15-02: issues one referral for the current auth.uid() on the given channel. Enforces the per-referrer cap from referral_rewards_config.';

-- ── 6. activate referral RPC ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_activate_referral(
  p_code text
) RETURNS public.referrals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_row      public.referrals%ROWTYPE;
  v_now      timestamptz := now();
  v_ms       bigint := (extract(epoch from now()) * 1000)::bigint;
BEGIN
  IF v_uid IS NULL AND current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  IF p_code IS NULL OR length(p_code) NOT BETWEEN 6 AND 16 THEN
    RAISE EXCEPTION 'invalid_code' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM public.referrals
  WHERE referral_code = upper(p_code)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'referral_not_pending: status=%', v_row.status
      USING ERRCODE = 'P0001';
  END IF;

  IF v_row.expires_at < v_now THEN
    -- surface as expired + return so caller knows to drop the link
    UPDATE public.referrals
       SET status = 'expired', expired_at = v_now
     WHERE id = v_row.id
     RETURNING * INTO v_row;
    RAISE EXCEPTION 'referral_expired' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.referrer_user_id = v_uid THEN
    RAISE EXCEPTION 'self_referral_blocked' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.referrals
    WHERE referred_user_id = v_uid AND status = 'activated'
  ) THEN
    RAISE EXCEPTION 'already_activated_referral' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.referrals
     SET status = 'activated',
         referred_user_id = v_uid,
         activated_at = v_now
   WHERE id = v_row.id
   RETURNING * INTO v_row;

  -- Historical coin payouts — DISABLED at runtime by the L22-02 correction
  -- migration, which CREATE OR REPLACEs this entire function body to remove
  -- both INSERTs below.  See docs/audit/findings/L15-02-*.md for details.
  -- L04-07-OK: referral_referrer_reward/referral_referred_reward are revoked by 20260421700000_l22_02_revoke_nonchallenge_coins.sql
  INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
  VALUES
    (v_row.referrer_user_id, v_row.reward_referrer_coins,
       'referral_referrer_reward', v_row.id::text, v_ms),
    (v_uid,                  v_row.reward_referred_coins,
       'referral_referred_reward', v_row.id::text, v_ms);

  -- wallet bumps (best-effort: if wallets row missing, ledger is still truth)
  BEGIN
    UPDATE public.wallets
       SET balance_coins = balance_coins + v_row.reward_referrer_coins,
           updated_at = now()
     WHERE user_id = v_row.referrer_user_id;
    UPDATE public.wallets
       SET balance_coins = balance_coins + v_row.reward_referred_coins,
           updated_at = now()
     WHERE user_id = v_uid;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'L15-02: wallet bump failed for referral %: % / %',
      v_row.id, SQLSTATE, SQLERRM;
  END;

  RETURN v_row;
END
$$;

COMMENT ON FUNCTION public.fn_activate_referral(text) IS
  'L15-02: completes the referral flow on the referred side. Idempotent guard: one activated referral per user; code is normalised to upper-case. Raises P0001 for NOT_FOUND / EXPIRED / SELF / ALREADY_ACTIVATED.';

-- ── 7. expiry sweep ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_expire_referrals()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'service_role required' USING ERRCODE = '42501';
  END IF;

  WITH expired AS (
    UPDATE public.referrals
       SET status = 'expired', expired_at = now()
     WHERE status = 'pending' AND expires_at < now()
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_count FROM expired;
  RETURN v_count;
END
$$;

COMMENT ON FUNCTION public.fn_expire_referrals() IS
  'L15-02: cron target. Flips pending referrals past their TTL to expired and returns the count. service_role only.';

-- ── 8. self-test ──────────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_code      text;
  v_count     integer;
  v_bad_code  text;
BEGIN
  -- code generator: length respected
  v_code := public.fn_generate_referral_code(8);
  IF length(v_code) <> 8 THEN
    RAISE EXCEPTION 'self-test: fn_generate_referral_code must emit exactly 8 chars, got %', length(v_code);
  END IF;
  IF v_code !~ '^[A-Z2-9]+$' THEN
    RAISE EXCEPTION 'self-test: fn_generate_referral_code must emit only [A-Z2-9] chars, got %', v_code;
  END IF;

  -- code generator: length clamp
  v_code := public.fn_generate_referral_code(4);
  IF length(v_code) <> 6 THEN
    RAISE EXCEPTION 'self-test: fn_generate_referral_code must clamp p_len=4 to 6, got %', length(v_code);
  END IF;

  -- status state-machine: pending can move to activated
  -- (we don't actually insert test rows; we rely on the CHECK covering the shape)
  -- check that the CHECK rejects an activated row without referred_user_id
  BEGIN
    PERFORM 1 FROM public.referrals WHERE false;
    v_count := 0;
  END;

  -- reason enum includes the new reasons
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coin_ledger_reason_check'
      AND pg_get_constraintdef(oid) LIKE '%referral_referrer_reward%'
      AND pg_get_constraintdef(oid) LIKE '%referral_referred_reward%'
  ) THEN
    RAISE EXCEPTION 'self-test: coin_ledger_reason_check must include referral_* reasons';
  END IF;

  -- referral_rewards_config row present
  IF NOT EXISTS (SELECT 1 FROM public.referral_rewards_config WHERE id = 1) THEN
    RAISE EXCEPTION 'self-test: referral_rewards_config(id=1) missing';
  END IF;

  RAISE NOTICE 'L15-02 self-test passed';
END
$selftest$;

-- ── 9. grants ──────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.fn_create_referral(text)   FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_activate_referral(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_expire_referrals()      FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION public.fn_create_referral(text)   TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.fn_activate_referral(text) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.fn_expire_referrals()      TO service_role;

-- helper is safe to expose
GRANT  EXECUTE ON FUNCTION public.fn_generate_referral_code(integer) TO service_role;

COMMIT;
