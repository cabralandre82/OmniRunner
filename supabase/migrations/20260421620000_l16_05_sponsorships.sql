-- ============================================================================
-- L16-05 — Sponsorships / brand integrations schema
-- Date: 2026-04-21
-- ============================================================================
-- Finding: Nike / Asics / Mizuno and other brands sponsor clubs + individual
-- athletes. The product has zero schema for:
--   • contract lifecycle (start, end, renewal),
--   • monthly coin payouts funded by the brand,
--   • equipment discount codes,
--   • athlete-level benefits (opt-in per athlete),
--   • audit trail of who approved the partnership.
--
-- This migration ships the canonical primitives so the portal (and, later,
-- the public-facing brand API) can drive the full lifecycle without leaking
-- PII and without letting coaches silently redirect coin payouts.
--
--   1. `public.brands` — append-only catalogue of sponsor brands (Nike,
--      Asics, …). Only platform_admin can INSERT/UPDATE. RLS open for
--      SELECT so athletes can see which brands are available.
--   2. `public.sponsorships` — one row per (group, brand, contract) with
--      state machine `draft → active | paused | ended | cancelled`,
--      monetary fields bounded via CHECK constraints, `approved_by` +
--      `approved_at` audit, `created_by` actor, `coin_budget_remaining`
--      derived counter.
--   3. `public.sponsorship_athletes` — per-athlete opt-in join table with
--      `enrolled_at` / `opted_out_at` timestamps so the brand sees
--      exactly who accepted (LGPD: athletes must opt in individually).
--   4. `fn_sponsorship_activate(id)` — admin RPC: validates contract
--      dates, flips status to `active`, stamps `approved_by/at`.
--   5. `fn_sponsorship_enroll_athlete(sponsorship_id)` — athlete-facing
--      RPC: enrols auth.uid() in the sponsorship (idempotent; raises
--      NOT_ACTIVE if contract isn't active; MEMBERSHIP_REQUIRED if the
--      athlete isn't a coaching_members row of the sponsored group).
--   6. `fn_sponsorship_opt_out_athlete(sponsorship_id)` — athlete-facing;
--      flips `opted_out_at` (idempotent).
--   7. `fn_sponsorship_distribute_monthly_coins(sponsorship_id, month)` —
--      service-role RPC target for the monthly cron. Credits the
--      per-athlete coin_ledger row with `reason = 'sponsorship_payout'`
--      (new ledger reason), bumps `coin_budget_used`, no-ops if already
--      distributed for the period.
--
-- All mutations go through SECURITY DEFINER RPCs. No direct INSERT/UPDATE
-- from anon/authenticated contexts on sponsorships or
-- sponsorship_athletes.

BEGIN;

-- ── 0. Extend coin_ledger reason enum with sponsorship_payout ───────────

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
      'referral_bonus',
      'referral_new_user',
      'redemption_payout',
      'custody_reversal',
      'championship_reward',
      'referral_referrer_reward',
      'referral_referred_reward',
      'sponsorship_payout'
    ])
  );

-- ── 1. Brands catalogue ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.brands (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          TEXT NOT NULL,
  display_name  TEXT NOT NULL,
  website_url   TEXT,
  logo_url      TEXT,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT brands_slug_shape CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,39}$'),
  CONSTRAINT brands_display_name_len CHECK (length(display_name) BETWEEN 2 AND 60),
  CONSTRAINT brands_website_url_https CHECK (website_url IS NULL OR (website_url ~ '^https://' AND length(website_url) <= 500)),
  CONSTRAINT brands_logo_url_https CHECK (logo_url IS NULL OR (logo_url ~ '^https://' AND length(logo_url) <= 500))
);

CREATE UNIQUE INDEX IF NOT EXISTS brands_slug_unique ON public.brands (slug);

COMMENT ON TABLE public.brands IS
  'L16-05: Catalogue of sponsor brands. Managed by platform_admin only; publicly readable via RLS.';

ALTER TABLE public.brands ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS brands_public_read ON public.brands;
CREATE POLICY brands_public_read ON public.brands
  FOR SELECT USING (active = TRUE);

DROP POLICY IF EXISTS brands_platform_admin_read ON public.brands;
CREATE POLICY brands_platform_admin_read ON public.brands
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

-- ── 2. Sponsorships table ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sponsorships (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id                  UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  brand_id                  UUID NOT NULL REFERENCES public.brands(id) ON DELETE RESTRICT,
  status                    TEXT NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft','active','paused','ended','cancelled')),
  contract_start            DATE NOT NULL,
  contract_end              DATE NOT NULL,
  monthly_coins_per_athlete INT NOT NULL DEFAULT 0,
  coin_budget_total         INT NOT NULL DEFAULT 0,
  coin_budget_used          INT NOT NULL DEFAULT 0,
  equipment_discount_pct    NUMERIC(5,2),
  terms_url                 TEXT,
  created_by                UUID REFERENCES auth.users(id),
  approved_by               UUID REFERENCES auth.users(id),
  approved_at               TIMESTAMPTZ,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT sponsorships_contract_window CHECK (contract_end > contract_start),
  CONSTRAINT sponsorships_monthly_coins_nonneg CHECK (monthly_coins_per_athlete BETWEEN 0 AND 100000),
  CONSTRAINT sponsorships_coin_budget_total_nonneg CHECK (coin_budget_total BETWEEN 0 AND 100000000),
  CONSTRAINT sponsorships_coin_budget_used_nonneg CHECK (coin_budget_used >= 0),
  CONSTRAINT sponsorships_coin_budget_used_within CHECK (coin_budget_used <= coin_budget_total),
  CONSTRAINT sponsorships_equipment_discount_range CHECK (equipment_discount_pct IS NULL OR (equipment_discount_pct >= 0 AND equipment_discount_pct <= 90)),
  CONSTRAINT sponsorships_terms_url_https CHECK (terms_url IS NULL OR (terms_url ~ '^https://' AND length(terms_url) <= 500)),
  CONSTRAINT sponsorships_active_requires_approval CHECK (
    status <> 'active' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS sponsorships_active_per_group_brand
  ON public.sponsorships (group_id, brand_id)
  WHERE status IN ('draft','active','paused');

CREATE INDEX IF NOT EXISTS sponsorships_group_idx ON public.sponsorships (group_id);
CREATE INDEX IF NOT EXISTS sponsorships_brand_idx ON public.sponsorships (brand_id);
CREATE INDEX IF NOT EXISTS sponsorships_active_idx
  ON public.sponsorships (status)
  WHERE status = 'active';

COMMENT ON TABLE public.sponsorships IS
  'L16-05: per-group brand partnership with lifecycle state machine and monthly coin budget. Mutation only through SECURITY DEFINER RPCs.';

ALTER TABLE public.sponsorships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sponsorships_staff_read ON public.sponsorships;
CREATE POLICY sponsorships_staff_read ON public.sponsorships
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = sponsorships.group_id
        AND cm.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- ── 3. Per-athlete opt-in join ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sponsorship_athletes (
  sponsorship_id UUID NOT NULL REFERENCES public.sponsorships(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  enrolled_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  opted_out_at   TIMESTAMPTZ,
  last_distributed_period DATE,
  PRIMARY KEY (sponsorship_id, user_id),
  CONSTRAINT sponsorship_athletes_timestamp_consistency CHECK (
    opted_out_at IS NULL OR opted_out_at >= enrolled_at
  )
);

CREATE INDEX IF NOT EXISTS sponsorship_athletes_user_idx
  ON public.sponsorship_athletes (user_id)
  WHERE opted_out_at IS NULL;

CREATE INDEX IF NOT EXISTS sponsorship_athletes_active_idx
  ON public.sponsorship_athletes (sponsorship_id)
  WHERE opted_out_at IS NULL;

COMMENT ON TABLE public.sponsorship_athletes IS
  'L16-05: LGPD-safe athlete opt-in join. Brand can only count athletes that explicitly enrolled.';

ALTER TABLE public.sponsorship_athletes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sponsorship_athletes_self_read ON public.sponsorship_athletes;
CREATE POLICY sponsorship_athletes_self_read ON public.sponsorship_athletes
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- ── 4. Admin RPCs ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_sponsorship_activate(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_is_platform_admin BOOLEAN := FALSE;
  v_row public.sponsorships;
BEGIN
  IF p_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ID' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row FROM public.sponsorships WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SPONSORSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF current_setting('role', true) <> 'service_role' THEN
    IF v_actor IS NULL THEN
      RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
    END IF;
    SELECT TRUE INTO v_is_platform_admin
    FROM public.profiles WHERE id = v_actor AND platform_role = 'admin';
    IF NOT COALESCE(v_is_platform_admin, FALSE) THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF v_row.status NOT IN ('draft','paused') THEN
    RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE = 'P0003';
  END IF;

  IF v_row.contract_end <= CURRENT_DATE THEN
    RAISE EXCEPTION 'CONTRACT_EXPIRED' USING ERRCODE = 'P0003';
  END IF;

  UPDATE public.sponsorships
  SET status = 'active',
      approved_by = v_actor,
      approved_at = now(),
      updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'approved_at', v_row.approved_at
  );
END;
$$;

COMMENT ON FUNCTION public.fn_sponsorship_activate(UUID) IS
  'Platform-admin RPC: flips sponsorship from draft/paused to active and stamps approved_by/at. Raises CONTRACT_EXPIRED when contract_end has passed.';

REVOKE ALL ON FUNCTION public.fn_sponsorship_activate(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sponsorship_activate(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_sponsorship_enroll_athlete(p_sponsorship_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_row public.sponsorships;
  v_is_member BOOLEAN := FALSE;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM public.sponsorships WHERE id = p_sponsorship_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SPONSORSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.status <> 'active' THEN
    RAISE EXCEPTION 'NOT_ACTIVE' USING ERRCODE = 'P0003';
  END IF;

  SELECT TRUE INTO v_is_member
  FROM public.coaching_members
  WHERE group_id = v_row.group_id AND user_id = v_actor;
  IF NOT COALESCE(v_is_member, FALSE) THEN
    RAISE EXCEPTION 'MEMBERSHIP_REQUIRED' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.sponsorship_athletes (sponsorship_id, user_id)
  VALUES (p_sponsorship_id, v_actor)
  ON CONFLICT (sponsorship_id, user_id) DO UPDATE
    SET opted_out_at = NULL
  WHERE sponsorship_athletes.opted_out_at IS NOT NULL;

  RETURN jsonb_build_object(
    'sponsorship_id', p_sponsorship_id,
    'user_id', v_actor,
    'enrolled', TRUE
  );
END;
$$;

COMMENT ON FUNCTION public.fn_sponsorship_enroll_athlete(UUID) IS
  'Athlete self-enrol in a sponsorship (idempotent). Requires coaching_members row in the sponsored group. Sponsorship must be active.';

REVOKE ALL ON FUNCTION public.fn_sponsorship_enroll_athlete(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sponsorship_enroll_athlete(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_sponsorship_opt_out_athlete(p_sponsorship_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  UPDATE public.sponsorship_athletes
  SET opted_out_at = now()
  WHERE sponsorship_id = p_sponsorship_id AND user_id = v_actor AND opted_out_at IS NULL;

  RETURN jsonb_build_object(
    'sponsorship_id', p_sponsorship_id,
    'user_id', v_actor,
    'opted_out', TRUE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_sponsorship_opt_out_athlete(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sponsorship_opt_out_athlete(UUID) TO authenticated, service_role;

-- ── 5. Monthly coin distribution (service-role cron target) ─────────────

CREATE OR REPLACE FUNCTION public.fn_sponsorship_distribute_monthly_coins(
  p_sponsorship_id UUID,
  p_period DATE DEFAULT (date_trunc('month', CURRENT_DATE)::DATE)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sp public.sponsorships;
  v_period DATE := date_trunc('month', p_period)::DATE;
  v_credited INT := 0;
  v_to_credit INT;
  v_athlete RECORD;
  v_budget_remaining INT;
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_ONLY' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_sp FROM public.sponsorships WHERE id = p_sponsorship_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SPONSORSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_sp.status <> 'active' THEN
    RAISE EXCEPTION 'NOT_ACTIVE' USING ERRCODE = 'P0003';
  END IF;
  IF v_sp.monthly_coins_per_athlete = 0 THEN
    RETURN jsonb_build_object(
      'sponsorship_id', p_sponsorship_id,
      'period', v_period,
      'credited_athletes', 0,
      'note', 'monthly_coins_per_athlete is zero; nothing to distribute'
    );
  END IF;

  FOR v_athlete IN
    SELECT sa.user_id
    FROM public.sponsorship_athletes sa
    WHERE sa.sponsorship_id = p_sponsorship_id
      AND sa.opted_out_at IS NULL
      AND (sa.last_distributed_period IS NULL OR sa.last_distributed_period < v_period)
    FOR UPDATE OF sa
  LOOP
    v_budget_remaining := v_sp.coin_budget_total - v_sp.coin_budget_used;
    IF v_budget_remaining < v_sp.monthly_coins_per_athlete THEN
      EXIT;
    END IF;

    v_to_credit := v_sp.monthly_coins_per_athlete;

    INSERT INTO public.coin_ledger (user_id, amount, reason, metadata)
    VALUES (
      v_athlete.user_id,
      v_to_credit,
      'sponsorship_payout',
      jsonb_build_object(
        'sponsorship_id', p_sponsorship_id,
        'brand_id', v_sp.brand_id,
        'period', v_period
      )
    );

    UPDATE public.sponsorship_athletes
    SET last_distributed_period = v_period
    WHERE sponsorship_id = p_sponsorship_id AND user_id = v_athlete.user_id;

    v_sp.coin_budget_used := v_sp.coin_budget_used + v_to_credit;
    v_credited := v_credited + 1;
  END LOOP;

  UPDATE public.sponsorships
  SET coin_budget_used = v_sp.coin_budget_used,
      updated_at = now()
  WHERE id = p_sponsorship_id;

  RETURN jsonb_build_object(
    'sponsorship_id', p_sponsorship_id,
    'period', v_period,
    'credited_athletes', v_credited,
    'budget_remaining', v_sp.coin_budget_total - v_sp.coin_budget_used
  );
END;
$$;

COMMENT ON FUNCTION public.fn_sponsorship_distribute_monthly_coins(UUID, DATE) IS
  'Service-role cron target. Credits monthly_coins_per_athlete to each enrolled athlete for the given period (idempotent via last_distributed_period). Stops when coin_budget_total is exhausted.';

REVOKE ALL ON FUNCTION public.fn_sponsorship_distribute_monthly_coins(UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sponsorship_distribute_monthly_coins(UUID, DATE) TO service_role;

-- ── 6. Self-test ────────────────────────────────────────────────────────

DO $self_test$
BEGIN
  PERFORM 1 FROM pg_constraint WHERE conname = 'sponsorships_contract_window';
  IF NOT FOUND THEN RAISE EXCEPTION 'self-test: sponsorships_contract_window missing'; END IF;

  PERFORM 1 FROM pg_constraint WHERE conname = 'sponsorships_coin_budget_used_within';
  IF NOT FOUND THEN RAISE EXCEPTION 'self-test: sponsorships_coin_budget_used_within missing'; END IF;

  PERFORM 1 FROM pg_constraint WHERE conname = 'sponsorships_active_requires_approval';
  IF NOT FOUND THEN RAISE EXCEPTION 'self-test: sponsorships_active_requires_approval missing'; END IF;

  PERFORM 1 FROM pg_constraint WHERE conname = 'coin_ledger_reason_check';
  IF NOT FOUND THEN RAISE EXCEPTION 'self-test: coin_ledger_reason_check missing after extension'; END IF;

  PERFORM 1 FROM pg_indexes
   WHERE indexname = 'sponsorships_active_per_group_brand';
  IF NOT FOUND THEN RAISE EXCEPTION 'self-test: sponsorships_active_per_group_brand index missing'; END IF;

  RAISE NOTICE 'L16-05 self-test OK';
END;
$self_test$;

COMMIT;
