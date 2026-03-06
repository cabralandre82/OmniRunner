-- ============================================================================
-- Billing Scale Hardening
-- Indexes, partial indexes, cleanup function, and RLS optimization
-- for 10k+ assessorias / 500k+ subscriptions / 18M+ webhook events/year.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Indexes for webhook event cleanup and temporal queries
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_pwe_created_at
  ON public.payment_webhook_events (created_at);

CREATE INDEX IF NOT EXISTS idx_pwe_unprocessed
  ON public.payment_webhook_events (created_at)
  WHERE processed = false;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Optimize asaas_subscription_map RLS — add group_id for direct lookup
--    instead of 3-way join through coaching_subscriptions → coaching_members
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.asaas_subscription_map
  ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES public.coaching_groups(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_asm_group
  ON public.asaas_subscription_map (group_id);

-- Backfill group_id from coaching_subscriptions
UPDATE public.asaas_subscription_map asm
SET group_id = cs.group_id
FROM public.coaching_subscriptions cs
WHERE asm.subscription_id = cs.id
  AND asm.group_id IS NULL;

-- Replace the 3-way join RLS policy with a direct lookup
DROP POLICY IF EXISTS "asm_staff_select" ON public.asaas_subscription_map;
CREATE POLICY "asm_staff_select"
  ON public.asaas_subscription_map FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = asaas_subscription_map.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Webhook event cleanup function (called by cron)
--    Deletes processed events older than 90 days, keeps unprocessed.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_cleanup_webhook_events(
  p_retention_days integer DEFAULT 90
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM public.payment_webhook_events
  WHERE processed = true
    AND created_at < now() - (p_retention_days || ' days')::interval;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cleanup_webhook_events(integer) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Batch billing function — creates Asaas customers+subscriptions
--    server-side instead of client-side loop. Records per-athlete results.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.billing_batch_jobs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  plan_id         uuid NOT NULL REFERENCES public.coaching_plans(id),
  athlete_ids     uuid[] NOT NULL,
  total           integer NOT NULL DEFAULT 0,
  succeeded       integer NOT NULL DEFAULT 0,
  failed          integer NOT NULL DEFAULT 0,
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  results         jsonb NOT NULL DEFAULT '[]',
  created_by      uuid NOT NULL REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz
);

ALTER TABLE public.billing_batch_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bbj_staff_select" ON public.billing_batch_jobs;
CREATE POLICY "bbj_staff_select"
  ON public.billing_batch_jobs FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_batch_jobs.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

DROP POLICY IF EXISTS "bbj_staff_insert" ON public.billing_batch_jobs;
CREATE POLICY "bbj_staff_insert"
  ON public.billing_batch_jobs FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_batch_jobs.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

CREATE INDEX IF NOT EXISTS idx_bbj_group_status
  ON public.billing_batch_jobs (group_id, status);

GRANT ALL ON TABLE public.billing_batch_jobs TO authenticated;
GRANT ALL ON TABLE public.billing_batch_jobs TO service_role;

COMMIT;
