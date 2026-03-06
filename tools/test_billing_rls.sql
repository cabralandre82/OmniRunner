-- ============================================================================
-- Billing Tables RLS Policy Tests
-- ============================================================================
-- Tests that athletes and coaches from different groups cannot access billing
-- tables: payment_provider_config, asaas_customer_map, asaas_subscription_map,
-- payment_webhook_events, billing_batch_jobs.
--
-- Run: psql $DATABASE_URL -f tools/test_billing_rls.sql
-- Uses ROLLBACK so no persistent changes.
-- Requires: auth.users with at least 2 users, migrations 20260316000000 + 20260316100000
-- ============================================================================

\set QUIET on
\pset format unaligned

BEGIN;

DO $$
DECLARE
  v_setup_user uuid;
  v_coach_b_user uuid;
  v_athlete_uuid uuid := gen_random_uuid();
  v_group_a uuid;
  v_group_b uuid;
  v_plan_id uuid;
  v_sub_id uuid;
  v_ppc_id uuid;
  v_acm_id uuid;
  v_asm_id uuid;
  v_pwe_id uuid;
  v_bbj_id uuid;
  v_cnt integer;
BEGIN
  -- Get users from auth.users (need 2: one for group A setup, one for coach in group B)
  SELECT id INTO v_setup_user FROM auth.users LIMIT 1;
  SELECT id INTO v_coach_b_user FROM auth.users WHERE id != v_setup_user LIMIT 1;

  IF v_setup_user IS NULL THEN
    RAISE EXCEPTION 'SKIP: No users in auth.users. Seed auth first.';
  END IF;

  -- ========== PHASE 1: Insert test data (as superuser, bypasses RLS) ==========
  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('RLS Test Group A', v_setup_user, 'Test', 'Test', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_a;

  INSERT INTO public.coaching_groups (name, coach_user_id, description, city, created_at_ms)
  VALUES ('RLS Test Group B', COALESCE(v_coach_b_user, v_setup_user), 'Test', 'Test', extract(epoch from now())::bigint * 1000)
  RETURNING id INTO v_group_b;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (COALESCE(v_coach_b_user, v_setup_user), v_group_b, 'Coach B', 'coach', extract(epoch from now())::bigint * 1000);

  INSERT INTO public.coaching_plans (group_id, name, monthly_price, created_by)
  VALUES (v_group_a, 'Test Plan', 99.00, v_setup_user)
  RETURNING id INTO v_plan_id;

  INSERT INTO public.coaching_subscriptions (group_id, athlete_user_id, plan_id)
  VALUES (v_group_a, v_setup_user, v_plan_id)
  RETURNING id INTO v_sub_id;

  INSERT INTO public.payment_provider_config (group_id, provider, api_key, environment)
  VALUES (v_group_a, 'asaas', 'test-key', 'sandbox')
  RETURNING id INTO v_ppc_id;

  INSERT INTO public.asaas_customer_map (group_id, athlete_user_id, asaas_customer_id)
  VALUES (v_group_a, v_setup_user, 'cus_test_001')
  RETURNING id INTO v_acm_id;

  INSERT INTO public.asaas_subscription_map (subscription_id, asaas_subscription_id, group_id)
  VALUES (v_sub_id, 'sub_test_001', v_group_a)
  RETURNING id INTO v_asm_id;

  INSERT INTO public.payment_webhook_events (group_id, event_type, payload)
  VALUES (v_group_a, 'PAYMENT_RECEIVED', '{}')
  RETURNING id INTO v_pwe_id;

  INSERT INTO public.billing_batch_jobs (group_id, plan_id, athlete_ids, total, created_by)
  VALUES (v_group_a, v_plan_id, ARRAY[v_setup_user], 1, v_setup_user)
  RETURNING id INTO v_bbj_id;

  RAISE NOTICE 'Setup: inserted test data for group_a=%', v_group_a;

  -- ========== PHASE 2: Switch to athlete context ==========
  -- Note: For RLS to apply, run this script as a non-superuser role (e.g. via
  -- Supabase SQL Editor with authenticated role). As postgres superuser, RLS is bypassed.
  PERFORM set_config('request.jwt.claims', '{"sub":"' || v_athlete_uuid::text || '","role":"authenticated"}', true);

  -- ----- payment_provider_config -----
  SELECT count(*) INTO v_cnt FROM payment_provider_config;
  IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: athlete can see payment_provider_config (% rows)', v_cnt; END IF;
  RAISE NOTICE 'PASS: athlete cannot select payment_provider_config';

  BEGIN
    INSERT INTO payment_provider_config (group_id, provider, api_key, environment)
    VALUES (v_group_a, 'asaas', 'x', 'sandbox');
    RAISE EXCEPTION 'RLS FAIL: athlete could insert payment_provider_config';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot insert payment_provider_config';
  END;

  BEGIN
    UPDATE payment_provider_config SET api_key = 'x' WHERE id = v_ppc_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could update payment_provider_config';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot update payment_provider_config';
  END;

  BEGIN
    DELETE FROM payment_provider_config WHERE id = v_ppc_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could delete payment_provider_config';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot delete payment_provider_config';
  END;

  -- ----- asaas_customer_map -----
  SELECT count(*) INTO v_cnt FROM asaas_customer_map;
  IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: athlete can see asaas_customer_map (% rows)', v_cnt; END IF;
  RAISE NOTICE 'PASS: athlete cannot select asaas_customer_map';

  BEGIN
    INSERT INTO asaas_customer_map (group_id, athlete_user_id, asaas_customer_id)
    VALUES (v_group_a, v_athlete_uuid, 'cus_x');
    RAISE EXCEPTION 'RLS FAIL: athlete could insert asaas_customer_map';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot insert asaas_customer_map';
  END;

  BEGIN
    UPDATE asaas_customer_map SET asaas_customer_id = 'x' WHERE id = v_acm_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could update asaas_customer_map';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot update asaas_customer_map';
  END;

  BEGIN
    DELETE FROM asaas_customer_map WHERE id = v_acm_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could delete asaas_customer_map';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot delete asaas_customer_map';
  END;

  -- ----- asaas_subscription_map -----
  SELECT count(*) INTO v_cnt FROM asaas_subscription_map;
  IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: athlete can see asaas_subscription_map (% rows)', v_cnt; END IF;
  RAISE NOTICE 'PASS: athlete cannot select asaas_subscription_map';

  BEGIN
    INSERT INTO asaas_subscription_map (subscription_id, asaas_subscription_id, group_id)
    VALUES (v_sub_id, 'sub_x', v_group_a);
    RAISE EXCEPTION 'RLS FAIL: athlete could insert asaas_subscription_map';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot insert asaas_subscription_map';
  END;

  BEGIN
    UPDATE asaas_subscription_map SET asaas_status = 'x' WHERE id = v_asm_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could update asaas_subscription_map';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot update asaas_subscription_map';
  END;

  BEGIN
    DELETE FROM asaas_subscription_map WHERE id = v_asm_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could delete asaas_subscription_map';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot delete asaas_subscription_map';
  END;

  -- ----- payment_webhook_events -----
  SELECT count(*) INTO v_cnt FROM payment_webhook_events;
  IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: athlete can see payment_webhook_events (% rows)', v_cnt; END IF;
  RAISE NOTICE 'PASS: athlete cannot select payment_webhook_events';

  BEGIN
    INSERT INTO payment_webhook_events (group_id, event_type, payload)
    VALUES (v_group_a, 'TEST', '{}');
    RAISE EXCEPTION 'RLS FAIL: athlete could insert payment_webhook_events';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot insert payment_webhook_events';
  END;

  BEGIN
    UPDATE payment_webhook_events SET processed = true WHERE id = v_pwe_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could update payment_webhook_events';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot update payment_webhook_events';
  END;

  BEGIN
    DELETE FROM payment_webhook_events WHERE id = v_pwe_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could delete payment_webhook_events';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot delete payment_webhook_events';
  END;

  -- ----- billing_batch_jobs -----
  SELECT count(*) INTO v_cnt FROM billing_batch_jobs;
  IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: athlete can see billing_batch_jobs (% rows)', v_cnt; END IF;
  RAISE NOTICE 'PASS: athlete cannot select billing_batch_jobs';

  BEGIN
    INSERT INTO billing_batch_jobs (group_id, plan_id, athlete_ids, total, created_by)
    VALUES (v_group_a, v_plan_id, ARRAY[v_setup_user], 1, v_athlete_uuid);
    RAISE EXCEPTION 'RLS FAIL: athlete could insert billing_batch_jobs';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot insert billing_batch_jobs';
  END;

  BEGIN
    UPDATE billing_batch_jobs SET status = 'failed' WHERE id = v_bbj_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could update billing_batch_jobs';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot update billing_batch_jobs';
  END;

  BEGIN
    DELETE FROM billing_batch_jobs WHERE id = v_bbj_id;
    RAISE EXCEPTION 'RLS FAIL: athlete could delete billing_batch_jobs';
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    IF SQLERRM LIKE 'RLS FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: athlete cannot delete billing_batch_jobs';
  END;

  -- ========== PHASE 3: Coach from DIFFERENT group cannot select ==========
  IF v_coach_b_user IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', '{"sub":"' || v_coach_b_user::text || '","role":"authenticated"}', true);

    SELECT count(*) INTO v_cnt FROM payment_provider_config;
    IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: coach from different group can see payment_provider_config (% rows)', v_cnt; END IF;
    RAISE NOTICE 'PASS: coach from different group cannot select payment_provider_config';

    SELECT count(*) INTO v_cnt FROM asaas_customer_map;
    IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: coach from different group can see asaas_customer_map (% rows)', v_cnt; END IF;
    RAISE NOTICE 'PASS: coach from different group cannot select asaas_customer_map';

    SELECT count(*) INTO v_cnt FROM asaas_subscription_map;
    IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: coach from different group can see asaas_subscription_map (% rows)', v_cnt; END IF;
    RAISE NOTICE 'PASS: coach from different group cannot select asaas_subscription_map';

    SELECT count(*) INTO v_cnt FROM payment_webhook_events;
    IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: coach from different group can see payment_webhook_events (% rows)', v_cnt; END IF;
    RAISE NOTICE 'PASS: coach from different group cannot select payment_webhook_events';

    SELECT count(*) INTO v_cnt FROM billing_batch_jobs;
    IF v_cnt > 0 THEN RAISE EXCEPTION 'RLS FAIL: coach from different group can see billing_batch_jobs (% rows)', v_cnt; END IF;
    RAISE NOTICE 'PASS: coach from different group cannot select billing_batch_jobs';
  ELSE
    RAISE NOTICE 'SKIP: coach from different group (need 2 users in auth.users)';
  END IF;

  RAISE NOTICE 'All billing RLS tests passed.';
END;
$$;

ROLLBACK;

\set QUIET off
