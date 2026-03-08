-- MEDIUM severity fixes from pre-release audit
-- 1. RLS on _role_migration_audit
-- 2. Add pg_temp to ~25 functions with search_path = public only
-- 3. Restrict GRANT on financial tables (custody_accounts, clearing_settlements)
-- 4. Add search_path to confirm_custody_deposit

-- ══════════════════════════════════════════════════════════════════
-- 1. Enable RLS on _role_migration_audit
-- ══════════════════════════════════════════════════════════════════
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = '_role_migration_audit') THEN
    EXECUTE 'ALTER TABLE public._role_migration_audit ENABLE ROW LEVEL SECURITY';
    -- Only service_role can read audit trail
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = '_role_migration_audit' AND policyname = 'service_only_audit') THEN
      EXECUTE 'CREATE POLICY service_only_audit ON public._role_migration_audit FOR ALL USING (false)';
    END IF;
  END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 2. Add pg_temp to all functions with search_path = public only
-- Using ALTER FUNCTION which is safe (no DROP/CREATE needed)
-- ══════════════════════════════════════════════════════════════════

-- Archive functions
DO $$ BEGIN ALTER FUNCTION public.fn_archive_old_sessions() SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;
DO $$ BEGIN ALTER FUNCTION public.fn_archive_old_ledger() SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- Partnership functions
DO $$ BEGIN ALTER FUNCTION public.fn_count_pending_partnerships(uuid) SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;
DO $$ BEGIN ALTER FUNCTION public.fn_list_partnerships(uuid) SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;
DO $$ BEGIN ALTER FUNCTION public.fn_request_partnership(uuid, uuid) SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;
DO $$ BEGIN ALTER FUNCTION public.fn_respond_partnership(uuid, text) SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;
DO $$ BEGIN ALTER FUNCTION public.fn_search_assessorias(text) SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;
DO $$ BEGIN ALTER FUNCTION public.fn_request_champ_join(uuid, uuid) SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;
DO $$ BEGIN ALTER FUNCTION public.fn_partner_championships(uuid) SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- Billing/Cleanup
DO $$ BEGIN ALTER FUNCTION public.fn_cleanup_webhook_events() SET search_path = public, pg_temp; EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- Delivery functions
DO $$ BEGIN
  ALTER FUNCTION public.fn_create_delivery_batch(uuid, text) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.fn_generate_delivery_items(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.fn_mark_item_published(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.fn_athlete_confirm_item(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.fn_close_delivery_batch(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- User mgmt
DO $$ BEGIN
  ALTER FUNCTION public.fn_delete_user_data(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.fn_notify_verification_change() SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- Badge inventory
DO $$ BEGIN
  ALTER FUNCTION public.fn_credit_badge_inventory(uuid, uuid, integer) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.fn_decrement_badge_inventory(uuid, uuid, integer) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.fn_fulfill_purchase(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- Strava backfill
DO $$ BEGIN
  ALTER FUNCTION public.backfill_strava_sessions() SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- Custody
DO $$ BEGIN
  ALTER FUNCTION public.confirm_custody_deposit(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 3. Restrict GRANT on financial tables: revoke ALL from authenticated,
--    grant only SELECT (read via RLS policies)
-- ══════════════════════════════════════════════════════════════════
DO $$ BEGIN
  REVOKE INSERT, UPDATE, DELETE ON public.custody_accounts FROM authenticated;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;
DO $$ BEGIN
  REVOKE INSERT, UPDATE, DELETE ON public.clearing_settlements FROM authenticated;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 4. custody_release_committed: add search_path
-- ══════════════════════════════════════════════════════════════════
DO $$ BEGIN
  ALTER FUNCTION public.custody_release_committed(uuid, integer) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
DO $$ BEGIN
  ALTER FUNCTION public.settle_clearing(uuid) SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
