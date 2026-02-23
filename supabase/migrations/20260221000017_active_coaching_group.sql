-- ============================================================================
-- Omni Runner — Enforce: atleta pertence a 1 assessoria + active_group
-- Date: 2026-02-22
-- Sprint: 17.5.1
-- Origin: DECISAO 038 / Phase 18 (Assessoria Ecosystem Core)
-- ============================================================================
-- A) profiles.active_coaching_group_id — FK to coaching_groups
-- B) Partial unique index on coaching_members(user_id) WHERE role='atleta'
--    ensures a single athlete can only belong to one coaching group globally
-- ============================================================================

BEGIN;

-- ── 1. Add active_coaching_group_id to profiles ──────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS active_coaching_group_id UUID
    REFERENCES public.coaching_groups(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_active_coaching_group
  ON public.profiles(active_coaching_group_id)
  WHERE active_coaching_group_id IS NOT NULL;

-- ── 2. Enforce: atleta can only exist in one coaching group globally ─────────
-- The existing UNIQUE(group_id, user_id) prevents duplicates within a group.
-- This partial unique index prevents the same atleta in multiple groups.

CREATE UNIQUE INDEX IF NOT EXISTS idx_coaching_members_atleta_unique
  ON public.coaching_members(user_id)
  WHERE role = 'atleta';

COMMIT;
