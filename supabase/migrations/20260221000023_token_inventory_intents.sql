-- ============================================================================
-- Omni Runner — coaching_token_inventory + token_intents
-- Date: 2026-02-22
-- Sprint: 17.6.0
-- Origin: DECISAO 038 / Phase 18 — Module C (Institutional Token Economy)
-- ============================================================================
-- coaching_token_inventory: per-group token stock (never negative)
-- token_intents: QR-based token operations with nonce, expiry, and lifecycle
-- ============================================================================

BEGIN;

-- ── 1. COACHING_TOKEN_INVENTORY ──────────────────────────────────────────────
-- Token stock per coaching group. Managed by platform/admin_master.

CREATE TABLE IF NOT EXISTS public.coaching_token_inventory (
  group_id          UUID PRIMARY KEY REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  available_tokens  INTEGER NOT NULL DEFAULT 0 CHECK (available_tokens >= 0),
  lifetime_issued   INTEGER NOT NULL DEFAULT 0,
  lifetime_burned   INTEGER NOT NULL DEFAULT 0,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.coaching_token_inventory ENABLE ROW LEVEL SECURITY;

-- Staff can read their group's inventory
CREATE POLICY "token_inventory_staff_read" ON public.coaching_token_inventory
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_token_inventory.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- Mutations via server (service_role) or RPC only — no direct client writes

-- ── 2. TOKEN_INTENTS ─────────────────────────────────────────────────────────
-- QR-based token operation intents with nonce-based idempotency.
-- Lifecycle: OPEN -> CONSUMED | EXPIRED | CANCELED

CREATE TABLE IF NOT EXISTS public.token_intents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  type            TEXT NOT NULL CHECK (type IN (
    'ISSUE_TO_ATHLETE',
    'BURN_FROM_ATHLETE',
    'CHAMP_BADGE_ACTIVATE'
  )),
  target_user_id  UUID REFERENCES auth.users(id),
  amount          INTEGER NOT NULL CHECK (amount > 0),
  nonce           TEXT NOT NULL UNIQUE,
  status          TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN (
    'OPEN', 'CONSUMED', 'EXPIRED', 'CANCELED'
  )),
  created_by      UUID NOT NULL REFERENCES auth.users(id),
  consumed_at     TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_token_intents_group ON public.token_intents(group_id, status);
CREATE INDEX idx_token_intents_nonce ON public.token_intents(nonce);
CREATE INDEX idx_token_intents_target ON public.token_intents(target_user_id, status)
  WHERE target_user_id IS NOT NULL;

ALTER TABLE public.token_intents ENABLE ROW LEVEL SECURITY;

-- Staff can read intents for their group
CREATE POLICY "token_intents_staff_read" ON public.token_intents
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = token_intents.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- Target athlete can read intents addressed to them
CREATE POLICY "token_intents_target_read" ON public.token_intents
  FOR SELECT USING (auth.uid() = target_user_id);

-- Mutations via server (service_role) or RPC only — no direct client writes

COMMIT;
