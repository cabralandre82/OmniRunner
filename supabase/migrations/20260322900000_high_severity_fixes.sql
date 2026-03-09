-- High severity fixes
SET search_path = public, pg_temp;

-- ============================================================
-- H-02: Grace period for PAYMENT_OVERDUE
-- ============================================================
DO $$ BEGIN
  ALTER TABLE public.coaching_subscriptions ADD COLUMN grace_until timestamptz;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- Function to convert expired grace periods to late status
CREATE OR REPLACE FUNCTION public.fn_expire_grace_subscriptions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count int;
BEGIN
  UPDATE public.coaching_subscriptions
     SET status = 'late',
         updated_at = NOW()
   WHERE status = 'grace'
     AND grace_until IS NOT NULL
     AND grace_until < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
