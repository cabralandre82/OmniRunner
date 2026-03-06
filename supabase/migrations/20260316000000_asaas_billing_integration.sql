-- ============================================================================
-- Asaas Billing Integration
-- Tables, indexes, RLS for payment provider config, customer/subscription
-- mapping, webhook events, CPF on members, and billing split fee.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. CPF on coaching_members (needed for Asaas customer creation)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_members
  ADD COLUMN IF NOT EXISTS cpf TEXT;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Payment Provider Config (one row per assessoria)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.payment_provider_config (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  provider      text NOT NULL DEFAULT 'asaas'
    CHECK (provider IN ('asaas')),
  api_key       text NOT NULL,
  wallet_id     text,
  environment   text NOT NULL DEFAULT 'sandbox'
    CHECK (environment IN ('sandbox', 'production')),
  is_active     boolean NOT NULL DEFAULT false,
  webhook_id    text,
  webhook_token text,
  connected_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_provider_group UNIQUE (group_id, provider)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Asaas Customer Map (athlete ↔ Asaas customer per assessoria)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.asaas_customer_map (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asaas_customer_id   text NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_asaas_customer UNIQUE (group_id, athlete_user_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Asaas Subscription Map (our subscription ↔ Asaas subscription)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.asaas_subscription_map (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id         uuid NOT NULL REFERENCES public.coaching_subscriptions(id) ON DELETE CASCADE,
  asaas_subscription_id   text NOT NULL,
  asaas_status            text NOT NULL DEFAULT 'ACTIVE',
  last_synced_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_asaas_subscription UNIQUE (subscription_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Payment Webhook Events (idempotency + audit log)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            uuid REFERENCES public.coaching_groups(id) ON DELETE SET NULL,
  asaas_event_id      text,
  event_type          text NOT NULL,
  asaas_payment_id    text,
  asaas_subscription_id text,
  payload             jsonb NOT NULL DEFAULT '{}',
  processed           boolean NOT NULL DEFAULT false,
  error_message       text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  processed_at        timestamptz,

  CONSTRAINT uq_asaas_event UNIQUE (asaas_event_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Indexes
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_ppc_group
  ON public.payment_provider_config (group_id);

CREATE INDEX IF NOT EXISTS idx_acm_group_athlete
  ON public.asaas_customer_map (group_id, athlete_user_id);

CREATE INDEX IF NOT EXISTS idx_acm_asaas_id
  ON public.asaas_customer_map (asaas_customer_id);

CREATE INDEX IF NOT EXISTS idx_asm_asaas_sub
  ON public.asaas_subscription_map (asaas_subscription_id);

CREATE INDEX IF NOT EXISTS idx_pwe_event_type
  ON public.payment_webhook_events (event_type, processed);

CREATE INDEX IF NOT EXISTS idx_pwe_asaas_payment
  ON public.payment_webhook_events (asaas_payment_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.payment_provider_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asaas_customer_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asaas_subscription_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

-- 7.1 payment_provider_config: only admin_master can manage
DROP POLICY IF EXISTS "ppc_staff_select" ON public.payment_provider_config;
CREATE POLICY "ppc_staff_select"
  ON public.payment_provider_config FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = payment_provider_config.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

DROP POLICY IF EXISTS "ppc_staff_insert" ON public.payment_provider_config;
CREATE POLICY "ppc_staff_insert"
  ON public.payment_provider_config FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = payment_provider_config.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

DROP POLICY IF EXISTS "ppc_staff_update" ON public.payment_provider_config;
CREATE POLICY "ppc_staff_update"
  ON public.payment_provider_config FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = payment_provider_config.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

DROP POLICY IF EXISTS "ppc_staff_delete" ON public.payment_provider_config;
CREATE POLICY "ppc_staff_delete"
  ON public.payment_provider_config FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = payment_provider_config.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- 7.2 asaas_customer_map: staff read, service_role write
DROP POLICY IF EXISTS "acm_staff_select" ON public.asaas_customer_map;
CREATE POLICY "acm_staff_select"
  ON public.asaas_customer_map FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = asaas_customer_map.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 7.3 asaas_subscription_map: staff can read via join
DROP POLICY IF EXISTS "asm_staff_select" ON public.asaas_subscription_map;
CREATE POLICY "asm_staff_select"
  ON public.asaas_subscription_map FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_subscriptions cs
      JOIN public.coaching_members cm ON cm.group_id = cs.group_id
      WHERE cs.id = asaas_subscription_map.subscription_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 7.4 payment_webhook_events: service_role only (Edge Functions)
DROP POLICY IF EXISTS "pwe_service_all" ON public.payment_webhook_events;
CREATE POLICY "pwe_service_all"
  ON public.payment_webhook_events FOR ALL USING (false);

-- 7.5 Allow staff to read webhook events for their group
DROP POLICY IF EXISTS "pwe_staff_select" ON public.payment_webhook_events;
CREATE POLICY "pwe_staff_select"
  ON public.payment_webhook_events FOR SELECT USING (
    group_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = payment_webhook_events.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. Expand fee_type CHECK and insert billing_split
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.platform_fee_config
  DROP CONSTRAINT IF EXISTS platform_fee_config_fee_type_check;

ALTER TABLE public.platform_fee_config
  ADD CONSTRAINT platform_fee_config_fee_type_check
    CHECK (fee_type IN ('clearing', 'swap', 'maintenance', 'billing_split'));

INSERT INTO public.platform_fee_config (fee_type, rate_pct, is_active)
VALUES ('billing_split', 2.50, true)
ON CONFLICT (fee_type) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. Grants
-- ═══════════════════════════════════════════════════════════════════════════

GRANT ALL ON TABLE public.payment_provider_config TO authenticated;
GRANT ALL ON TABLE public.payment_provider_config TO service_role;

GRANT ALL ON TABLE public.asaas_customer_map TO authenticated;
GRANT ALL ON TABLE public.asaas_customer_map TO service_role;

GRANT ALL ON TABLE public.asaas_subscription_map TO authenticated;
GRANT ALL ON TABLE public.asaas_subscription_map TO service_role;

GRANT ALL ON TABLE public.payment_webhook_events TO authenticated;
GRANT ALL ON TABLE public.payment_webhook_events TO service_role;

COMMIT;
