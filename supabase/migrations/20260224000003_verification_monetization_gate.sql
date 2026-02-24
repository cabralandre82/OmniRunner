-- ============================================================================
-- Omni Runner — Monetization Gate (Impossible to Bypass)
-- Date: 2026-02-24
-- Sprint: VERIFIED-3 (Sprint 22.2.0)
-- ============================================================================
--
-- THREE layers of enforcement — defense-in-depth:
--
--   Layer 1: Edge Function code (challenge-create, challenge-join)
--            → validates BEFORE insert, returns UX-friendly error
--   Layer 2: RLS policy on challenges INSERT
--            → blocks direct client access (anon key + JWT)
--   Layer 3: DB triggers on challenges + challenge_participants
--            → fires even for service_role (bypasses RLS)
--            → last line of defense, impossible to circumvent
--
-- RULE (CONGELADA):
--   entry_fee_coins = 0  → any user
--   entry_fee_coins > 0  → only VERIFIED users (create AND join)
--   ZERO override. ZERO backdoor. ZERO admin set.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. RLS: Narrow existing INSERT policy on challenges
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Original policy: auth.uid() = creator_user_id
-- New policy adds: entry_fee_coins = 0 OR is_user_verified(auth.uid())
--
-- This only affects direct client access (anon key + JWT).
-- EFs use service_role and bypass RLS entirely.

DROP POLICY IF EXISTS "challenges_insert_auth" ON public.challenges;

CREATE POLICY "challenges_insert_auth" ON public.challenges
  FOR INSERT WITH CHECK (
    auth.uid() = creator_user_id
    AND (
      entry_fee_coins = 0
      OR public.is_user_verified(auth.uid())
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. DB TRIGGER: enforce verified gate on challenges INSERT/UPDATE
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Fires BEFORE INSERT and BEFORE UPDATE (on entry_fee_coins column).
-- Works even for service_role callers — this is the strongest enforcement.
-- If entry_fee_coins > 0, the creator must be VERIFIED.
-- On UPDATE, blocks raising entry_fee_coins from 0 to >0 without VERIFIED.

CREATE OR REPLACE FUNCTION public.fn_enforce_verified_stake_gate()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.entry_fee_coins > 0 THEN
    IF NOT public.is_user_verified(NEW.creator_user_id) THEN
      RAISE EXCEPTION 'ATHLETE_NOT_VERIFIED: criar desafio com stake>0 exige status VERIFIED'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_challenges_verified_stake_gate ON public.challenges;

CREATE TRIGGER trg_challenges_verified_stake_gate
  BEFORE INSERT OR UPDATE OF entry_fee_coins
  ON public.challenges
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_enforce_verified_stake_gate();

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. DB TRIGGER: enforce verified gate on challenge_participants INSERT
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Fires BEFORE INSERT on challenge_participants.
-- Looks up the challenge's entry_fee_coins; if >0, the joining user
-- must be VERIFIED.
--
-- This catches:
--   - Direct inserts (should never happen, but defense-in-depth)
--   - EF service_role inserts (if EF validation is somehow bypassed)
--   - The creator joining their own challenge (inserted in challenge-create)

CREATE OR REPLACE FUNCTION public.fn_enforce_verified_join_gate()
RETURNS TRIGGER AS $$
DECLARE
  _fee INTEGER;
BEGIN
  SELECT c.entry_fee_coins INTO _fee
  FROM public.challenges c
  WHERE c.id = NEW.challenge_id;

  IF _fee IS NOT NULL AND _fee > 0 THEN
    IF NOT public.is_user_verified(NEW.user_id) THEN
      RAISE EXCEPTION 'ATHLETE_NOT_VERIFIED: participar de desafio com stake>0 exige status VERIFIED'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_participants_verified_join_gate ON public.challenge_participants;

CREATE TRIGGER trg_participants_verified_join_gate
  BEFORE INSERT
  ON public.challenge_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_enforce_verified_join_gate();

COMMIT;
