-- ============================================================================
-- Omni Runner — Fix OmniCoin distribution visibility
-- Date: 2026-04-15
-- Problem: coin_ledger has a "ledger_own_read" RLS policy that only lets
--   users see their own rows. Coaches querying athletes' coin entries saw 0
--   distributed coins even when distributions had been made.
--   Additionally, distribute-coins/route.ts was not populating issuer_group_id.
-- Fix:
--   1. Add RLS policy so group admins/coaches can read ledger entries where
--      issuer_group_id = their group (needed for Flutter StaffCreditsScreen
--      and portal distributions page).
--   2. Provide a repair query to backfill issuer_group_id for legacy entries
--      that were inserted without it.
-- ============================================================================

-- ── 1. Add coach-visibility policy ───────────────────────────────────────────
-- Allows any admin_master or coach of a group to SELECT coin_ledger rows
-- that were issued by their group (issuer_group_id = their group).
-- The existing "ledger_own_read" policy remains for athlete self-service.

CREATE POLICY "group_staff_read_issued_ledger" ON public.coin_ledger
  FOR SELECT USING (
    issuer_group_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coin_ledger.issuer_group_id
        AND cm.user_id   = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- ── 2. Backfill issuer_group_id for existing institution_token_issue entries ─
-- For entries that went through token-consume-intent but lack issuer_group_id
-- due to earlier bugs, try to infer it from token_intents.ref_id.
-- Safe: only updates rows where issuer_group_id IS NULL.

UPDATE public.coin_ledger cl
SET issuer_group_id = ti.group_id
FROM public.token_intents ti
WHERE cl.reason      = 'institution_token_issue'
  AND cl.issuer_group_id IS NULL
  AND cl.ref_id      = ti.id::text
  AND ti.group_id    IS NOT NULL;

-- ── 3. Grant fn_sum_coin_ledger_by_group to authenticated ────────────────────
-- Ensure the SECURITY DEFINER helper is callable by app users (Flutter/portal).

DO $$
BEGIN
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_sum_coin_ledger_by_group(uuid) TO authenticated';
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_sum_coin_ledger_by_group not found, skipping grant';
END;
$$;
